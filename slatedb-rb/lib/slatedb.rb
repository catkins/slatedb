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
  end
end
