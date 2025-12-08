# frozen_string_literal: true

require_relative "slatedb/version"

# Load the native extension
begin
  RUBY_VERSION =~ /(\d+\.\d+)/
  require "slatedb/#{$1}/slatedb_ext"
rescue LoadError
  require "slatedb/slatedb_ext"
end

module SlateDb
  class Database
    class << self
      # Open a database at the given path.
      #
      # @param path [String] The path identifier for the database
      # @param url [String, nil] Optional object store URL (e.g., "s3://bucket/path")
      # @yield [db] If a block is given, yields the database and ensures it's closed
      # @return [Database] The opened database (or block result if block given)
      #
      # @example Open a database
      #   db = SlateDb::Database.open("/tmp/mydb")
      #   db.put("key", "value")
      #   db.close
      #
      # @example Open with block (auto-close)
      #   SlateDb::Database.open("/tmp/mydb") do |db|
      #     db.put("key", "value")
      #   end # automatically closed
      #
      # @example Open with S3 backend
      #   db = SlateDb::Database.open("/tmp/mydb", url: "s3://mybucket/path")
      #
      def open(path, url: nil, &block)
        db = _open(path, url)

        if block_given?
          begin
            yield db
          ensure
            db.close rescue nil
          end
        else
          db
        end
      end
    end

    # Get a value by key.
    #
    # @param key [String] The key to look up
    # @param durability_filter [String, nil] Filter by durability level ("remote" or "memory")
    # @param dirty [Boolean, nil] Whether to include uncommitted data
    # @param cache_blocks [Boolean, nil] Whether to cache blocks
    # @return [String, nil] The value, or nil if not found
    #
    # @example Basic get
    #   value = db.get("mykey")
    #
    # @example Get with options
    #   value = db.get("mykey", durability_filter: "memory", dirty: true)
    #
    def get(key, durability_filter: nil, dirty: nil, cache_blocks: nil)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?

      if opts.empty?
        _get(key)
      else
        _get_with_options(key, opts)
      end
    end

    # Store a key-value pair.
    #
    # @param key [String] The key to store
    # @param value [String] The value to store
    # @param ttl [Integer, nil] Time-to-live in milliseconds
    # @param await_durable [Boolean] Whether to wait for durability (default: true)
    # @return [void]
    #
    # @example Basic put
    #   db.put("mykey", "myvalue")
    #
    # @example Put with TTL
    #   db.put("mykey", "myvalue", ttl: 60_000) # expires in 60 seconds
    #
    # @example Put without waiting for durability
    #   db.put("mykey", "myvalue", await_durable: false)
    #
    def put(key, value, ttl: nil, await_durable: nil)
      opts = {}
      opts[:ttl] = ttl if ttl
      opts[:await_durable] = await_durable unless await_durable.nil?

      if opts.empty?
        _put(key, value)
      else
        _put_with_options(key, value, opts)
      end
    end

    # Delete a key.
    #
    # @param key [String] The key to delete
    # @param await_durable [Boolean] Whether to wait for durability (default: true)
    # @return [void]
    #
    # @example Basic delete
    #   db.delete("mykey")
    #
    # @example Delete without waiting for durability
    #   db.delete("mykey", await_durable: false)
    #
    def delete(key, await_durable: nil)
      if await_durable.nil?
        _delete(key)
      else
        _delete_with_options(key, { await_durable: await_durable })
      end
    end

    # Scan a range of keys.
    #
    # @param start_key [String] The start key (inclusive)
    # @param end_key [String, nil] The end key (exclusive). If nil, scans to end.
    # @param durability_filter [String, nil] Filter by durability level ("remote" or "memory")
    # @param dirty [Boolean, nil] Whether to include uncommitted data
    # @param read_ahead_bytes [Integer, nil] Number of bytes to read ahead
    # @param cache_blocks [Boolean, nil] Whether to cache blocks
    # @param max_fetch_tasks [Integer, nil] Maximum number of fetch tasks
    # @return [Iterator] An iterator over key-value pairs
    #
    # @example Basic scan
    #   iter = db.scan("a")
    #   while entry = iter.next_entry
    #     key, value = entry
    #     puts "#{key}: #{value}"
    #   end
    #
    # @example Scan with range
    #   iter = db.scan("a", "z")
    #
    # @example Scan with block
    #   db.scan("user:") do |key, value|
    #     puts "#{key}: #{value}"
    #   end
    #
    def scan(start_key, end_key = nil, durability_filter: nil, dirty: nil,
             read_ahead_bytes: nil, cache_blocks: nil, max_fetch_tasks: nil, &block)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:read_ahead_bytes] = read_ahead_bytes if read_ahead_bytes
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?
      opts[:max_fetch_tasks] = max_fetch_tasks if max_fetch_tasks

      iter = if opts.empty?
               _scan(start_key, end_key)
             else
               _scan_with_options(start_key, end_key, opts)
             end

      if block_given?
        iter.each(&block)
      else
        iter
      end
    end

    # Write a batch of operations atomically.
    #
    # @param batch [WriteBatch] The batch to write
    # @param await_durable [Boolean] Whether to wait for durability (default: true)
    # @return [void]
    #
    # @example Write a batch
    #   batch = SlateDb::WriteBatch.new
    #   batch.put("key1", "value1")
    #   batch.put("key2", "value2")
    #   batch.delete("key3")
    #   db.write(batch)
    #
    # @example Using batch block helper
    #   db.batch do |b|
    #     b.put("key1", "value1")
    #     b.put("key2", "value2")
    #   end
    #
    def write(batch, await_durable: nil)
      if await_durable.nil?
        _write(batch)
      else
        _write_with_options(batch, { await_durable: await_durable })
      end
    end

    # Create and write a batch using a block.
    #
    # @param await_durable [Boolean] Whether to wait for durability (default: true)
    # @yield [batch] Yields a WriteBatch to the block
    # @return [void]
    #
    # @example
    #   db.batch do |b|
    #     b.put("key1", "value1")
    #     b.put("key2", "value2")
    #     b.delete("old_key")
    #   end
    #
    def batch(await_durable: nil, &block)
      b = WriteBatch.new
      yield b
      write(b, await_durable: await_durable)
    end

    # Begin a new transaction.
    #
    # @param isolation [Symbol, String] Isolation level (:snapshot or :serializable)
    # @yield [txn] If a block is given, yields the transaction and auto-commits/rollbacks
    # @return [Transaction, Object] The transaction (or block result if block given)
    #
    # @example Manual transaction management
    #   txn = db.begin_transaction
    #   txn.put("key", "value")
    #   txn.commit
    #
    # @example Block-based transaction (auto-commit)
    #   db.transaction do |txn|
    #     txn.put("key", "value")
    #     txn.get("other_key")
    #   end # automatically committed
    #
    # @example Serializable isolation
    #   db.transaction(isolation: :serializable) do |txn|
    #     val = txn.get("counter")
    #     txn.put("counter", (val.to_i + 1).to_s)
    #   end
    #
    def begin_transaction(isolation: nil)
      isolation_str = isolation&.to_s
      _begin_transaction(isolation_str)
    end

    # Execute a block within a transaction.
    #
    # The transaction is automatically committed if the block succeeds,
    # or rolled back if an exception is raised.
    #
    # @param isolation [Symbol, String] Isolation level (:snapshot or :serializable)
    # @yield [txn] Yields the transaction to the block
    # @return [Object] The result of the block
    #
    # @example
    #   result = db.transaction do |txn|
    #     old_val = txn.get("counter") || "0"
    #     new_val = (old_val.to_i + 1).to_s
    #     txn.put("counter", new_val)
    #     new_val
    #   end
    #
    def transaction(isolation: nil)
      txn = begin_transaction(isolation: isolation)
      begin
        result = yield txn
        txn.commit
        result
      rescue => e
        txn.rollback rescue nil
        raise
      end
    end

    # Create a snapshot for consistent reads.
    #
    # @yield [snapshot] If a block is given, yields the snapshot and auto-closes
    # @return [Snapshot, Object] The snapshot (or block result if block given)
    #
    # @example Manual snapshot management
    #   snapshot = db.snapshot
    #   snapshot.get("key")
    #   snapshot.close
    #
    # @example Block-based snapshot (auto-close)
    #   db.snapshot do |snap|
    #     snap.get("key1")
    #     snap.get("key2")
    #   end # automatically closed
    #
    def snapshot(&block)
      snap = _snapshot

      if block_given?
        begin
          yield snap
        ensure
          snap.close rescue nil
        end
      else
        snap
      end
    end
  end

  class Iterator
    include Enumerable

    # Iterate over all entries.
    #
    # @yield [key, value] Yields each key-value pair
    # @return [self, Enumerator] Returns self if block given, otherwise an Enumerator
    #
    # @example
    #   iter.each do |key, value|
    #     puts "#{key}: #{value}"
    #   end
    #
    # @example With Enumerable methods
    #   iter.map { |k, v| [k.upcase, v] }
    #   iter.select { |k, v| k.start_with?("user:") }
    #
    def each(&block)
      return to_enum(:each) unless block_given?

      while (entry = next_entry)
        yield entry
      end

      self
    end
  end

  class WriteBatch
    # Add a put operation to the batch.
    #
    # @param key [String] The key to store
    # @param value [String] The value to store
    # @param ttl [Integer, nil] Time-to-live in milliseconds
    # @return [self] Returns self for method chaining
    #
    # @example
    #   batch.put("key", "value")
    #   batch.put("key2", "value2", ttl: 60_000)
    #
    def put(key, value, ttl: nil)
      if ttl
        _put_with_options(key, value, { ttl: ttl })
      else
        _put(key, value)
      end
      self
    end

    # Add a delete operation to the batch.
    #
    # @param key [String] The key to delete
    # @return [self] Returns self for method chaining
    #
    # @example
    #   batch.delete("key")
    #
    def delete(key)
      _delete(key)
      self
    end
  end

  class Transaction
    # Get a value by key within the transaction.
    #
    # @param key [String] The key to look up
    # @param durability_filter [String, nil] Filter by durability level
    # @param dirty [Boolean, nil] Whether to include uncommitted data
    # @param cache_blocks [Boolean, nil] Whether to cache blocks
    # @return [String, nil] The value, or nil if not found
    #
    def get(key, durability_filter: nil, dirty: nil, cache_blocks: nil)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?

      if opts.empty?
        _get(key)
      else
        _get_with_options(key, opts)
      end
    end

    # Store a key-value pair within the transaction.
    #
    # @param key [String] The key to store
    # @param value [String] The value to store
    # @param ttl [Integer, nil] Time-to-live in milliseconds
    # @return [void]
    #
    def put(key, value, ttl: nil)
      if ttl
        _put_with_options(key, value, { ttl: ttl })
      else
        _put(key, value)
      end
    end

    # Delete a key within the transaction.
    #
    # @param key [String] The key to delete
    # @return [void]
    #
    def delete(key)
      _delete(key)
    end

    # Scan a range of keys within the transaction.
    #
    # @param start_key [String] The start key (inclusive)
    # @param end_key [String, nil] The end key (exclusive)
    # @return [Iterator] An iterator over key-value pairs
    #
    def scan(start_key, end_key = nil, durability_filter: nil, dirty: nil,
             read_ahead_bytes: nil, cache_blocks: nil, max_fetch_tasks: nil, &block)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:read_ahead_bytes] = read_ahead_bytes if read_ahead_bytes
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?
      opts[:max_fetch_tasks] = max_fetch_tasks if max_fetch_tasks

      iter = if opts.empty?
               _scan(start_key, end_key)
             else
               _scan_with_options(start_key, end_key, opts)
             end

      if block_given?
        iter.each(&block)
      else
        iter
      end
    end
  end

  class Snapshot
    # Get a value by key from the snapshot.
    #
    # @param key [String] The key to look up
    # @param durability_filter [String, nil] Filter by durability level
    # @param dirty [Boolean, nil] Whether to include uncommitted data
    # @param cache_blocks [Boolean, nil] Whether to cache blocks
    # @return [String, nil] The value, or nil if not found
    #
    def get(key, durability_filter: nil, dirty: nil, cache_blocks: nil)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?

      if opts.empty?
        _get(key)
      else
        _get_with_options(key, opts)
      end
    end

    # Scan a range of keys from the snapshot.
    #
    # @param start_key [String] The start key (inclusive)
    # @param end_key [String, nil] The end key (exclusive)
    # @return [Iterator] An iterator over key-value pairs
    #
    def scan(start_key, end_key = nil, durability_filter: nil, dirty: nil,
             read_ahead_bytes: nil, cache_blocks: nil, max_fetch_tasks: nil, &block)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:read_ahead_bytes] = read_ahead_bytes if read_ahead_bytes
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?
      opts[:max_fetch_tasks] = max_fetch_tasks if max_fetch_tasks

      iter = if opts.empty?
               _scan(start_key, end_key)
             else
               _scan_with_options(start_key, end_key, opts)
             end

      if block_given?
        iter.each(&block)
      else
        iter
      end
    end
  end

  class Reader
    class << self
      # Open a read-only reader at the given path.
      #
      # @param path [String] The path identifier for the database
      # @param url [String, nil] Optional object store URL
      # @param checkpoint_id [String, nil] Optional checkpoint UUID to read at
      # @param manifest_poll_interval [Integer, nil] Poll interval in milliseconds
      # @param checkpoint_lifetime [Integer, nil] Checkpoint lifetime in milliseconds
      # @param max_memtable_bytes [Integer, nil] Maximum memtable size in bytes
      # @yield [reader] If a block is given, yields the reader and ensures it's closed
      # @return [Reader] The opened reader (or block result if block given)
      #
      # @example Open a reader
      #   reader = SlateDb::Reader.open("/tmp/mydb")
      #   value = reader.get("key")
      #   reader.close
      #
      # @example Open with block (auto-close)
      #   SlateDb::Reader.open("/tmp/mydb") do |reader|
      #     reader.get("key")
      #   end # automatically closed
      #
      # @example Open at a specific checkpoint
      #   reader = SlateDb::Reader.open("/tmp/mydb", checkpoint_id: "uuid-here")
      #
      def open(path, url: nil, checkpoint_id: nil,
               manifest_poll_interval: nil, checkpoint_lifetime: nil,
               max_memtable_bytes: nil, &block)
        opts = {}
        opts[:manifest_poll_interval] = manifest_poll_interval if manifest_poll_interval
        opts[:checkpoint_lifetime] = checkpoint_lifetime if checkpoint_lifetime
        opts[:max_memtable_bytes] = max_memtable_bytes if max_memtable_bytes

        reader = _open(path, url, checkpoint_id, opts)

        if block_given?
          begin
            yield reader
          ensure
            reader.close rescue nil
          end
        else
          reader
        end
      end
    end

    # Get a value by key.
    #
    # @param key [String] The key to look up
    # @param durability_filter [String, nil] Filter by durability level ("remote" or "memory")
    # @param dirty [Boolean, nil] Whether to include uncommitted data
    # @param cache_blocks [Boolean, nil] Whether to cache blocks
    # @return [String, nil] The value, or nil if not found
    #
    def get(key, durability_filter: nil, dirty: nil, cache_blocks: nil)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?

      if opts.empty?
        _get(key)
      else
        _get_with_options(key, opts)
      end
    end

    # Scan a range of keys.
    #
    # @param start_key [String] The start key (inclusive)
    # @param end_key [String, nil] The end key (exclusive)
    # @return [Iterator] An iterator over key-value pairs
    #
    def scan(start_key, end_key = nil, durability_filter: nil, dirty: nil,
             read_ahead_bytes: nil, cache_blocks: nil, max_fetch_tasks: nil, &block)
      opts = {}
      opts[:durability_filter] = durability_filter.to_s if durability_filter
      opts[:dirty] = dirty unless dirty.nil?
      opts[:read_ahead_bytes] = read_ahead_bytes if read_ahead_bytes
      opts[:cache_blocks] = cache_blocks unless cache_blocks.nil?
      opts[:max_fetch_tasks] = max_fetch_tasks if max_fetch_tasks

      iter = if opts.empty?
               _scan(start_key, end_key)
             else
               _scan_with_options(start_key, end_key, opts)
             end

      if block_given?
        iter.each(&block)
      else
        iter
      end
    end
  end

  class Admin
    class << self
      # Create an admin handle for a database path/object store.
      #
      # @param path [String] Database path
      # @param url [String, nil] Optional object store URL
      # @return [Admin] The admin handle
      #
      # @example
      #   admin = SlateDb::Admin.new("/tmp/mydb")
      #   checkpoints = admin.list_checkpoints
      #
      def new(path, url: nil)
        _new(path, url)
      end
    end

    # Read the latest or a specific manifest as a JSON string.
    #
    # @param id [Integer, nil] Optional manifest id to read. If nil, reads the latest.
    # @return [String, nil] JSON string of the manifest, or nil if no manifests exist
    #
    # @example
    #   json = admin.read_manifest
    #   json = admin.read_manifest(123)
    #
    def read_manifest(id = nil)
      _read_manifest(id)
    end

    # List manifests within an optional [start, end) range as JSON.
    #
    # @param start [Integer, nil] Optional inclusive start id
    # @param end_id [Integer, nil] Optional exclusive end id
    # @return [String] JSON string containing a list of manifest metadata
    #
    # @example
    #   json = admin.list_manifests
    #   json = admin.list_manifests(start: 1, end_id: 10)
    #
    def list_manifests(start: nil, end_id: nil)
      _list_manifests(start, end_id)
    end

    # Create a detached checkpoint.
    #
    # @param lifetime [Integer, nil] Checkpoint lifetime in milliseconds
    # @param source [String, nil] Source checkpoint UUID string to extend/refresh
    # @param name [String, nil] Checkpoint name
    # @return [Hash] Hash with :id (UUID string) and :manifest_id (Integer)
    #
    # @example
    #   result = admin.create_checkpoint(name: "my_checkpoint")
    #   puts result[:id]         # => "uuid-string"
    #   puts result[:manifest_id] # => 7
    #
    def create_checkpoint(lifetime: nil, source: nil, name: nil)
      opts = {}
      opts[:lifetime] = lifetime if lifetime
      opts[:source] = source if source
      opts[:name] = name if name
      _create_checkpoint(opts)
    end

    # List known checkpoints for the database.
    #
    # @param name [String, nil] Optional checkpoint name filter
    # @return [Array<Hash>] Array of checkpoint hashes
    #
    # @example
    #   checkpoints = admin.list_checkpoints
    #   checkpoints.each do |cp|
    #     puts "#{cp[:id]}: #{cp[:name]}"
    #   end
    #
    def list_checkpoints(name: nil)
      _list_checkpoints(name)
    end

    # Refresh a checkpoint's lifetime.
    #
    # @param id [String] Checkpoint UUID string
    # @param lifetime [Integer, nil] New lifetime in milliseconds
    # @return [void]
    #
    # @example
    #   admin.refresh_checkpoint("uuid-here", lifetime: 60_000)
    #
    def refresh_checkpoint(id, lifetime: nil)
      _refresh_checkpoint(id, lifetime)
    end

    # Delete a checkpoint.
    #
    # @param id [String] Checkpoint UUID string
    # @return [void]
    #
    # @example
    #   admin.delete_checkpoint("uuid-here")
    #
    def delete_checkpoint(id)
      _delete_checkpoint(id)
    end

    # Run garbage collection once.
    #
    # @param min_age [Integer, nil] Minimum age in milliseconds for objects to be collected
    # @return [void]
    #
    # @example
    #   admin.run_gc(min_age: 3600_000) # 1 hour
    #
    def run_gc(min_age: nil)
      opts = {}
      opts[:min_age] = min_age if min_age
      _run_gc(opts)
    end
  end
end
