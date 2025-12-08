# SlateDB Ruby Bindings

Ruby bindings for [SlateDB](https://slatedb.io), a cloud-native embedded key-value store built on object storage.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slatedb'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install slatedb
```

## Usage

### Basic Operations

```ruby
require 'slatedb'

# Open a database with in-memory storage (for testing)
db = SlateDb::Database.open("/tmp/mydb")

# Store a value
db.put("hello", "world")

# Retrieve a value
value = db.get("hello")  # => "world"

# Delete a value
db.delete("hello")

# Close the database
db.close
```

### Block Form (Recommended)

The block form automatically closes the database when the block exits:

```ruby
SlateDb::Database.open("/tmp/mydb") do |db|
  db.put("key", "value")
  db.get("key")  # => "value"
end  # automatically closed
```

### Persistent Storage

For persistent storage, provide an object store URL:

```ruby
# Local filesystem
SlateDb::Database.open("/tmp/mydb", url: "file:///tmp/mydb") do |db|
  db.put("key", "value")
end

# S3 (requires AWS credentials in environment)
SlateDb::Database.open("mydb", url: "s3://mybucket/path") do |db|
  db.put("key", "value")
end
```

### Options

#### Put Options

```ruby
# Set TTL (time-to-live) in milliseconds
db.put("key", "value", ttl: 60_000)  # expires in 60 seconds

# Don't wait for durability
db.put("key", "value", await_durable: false)
```

#### Get Options

```ruby
# Filter by durability level
db.get("key", durability_filter: "memory")
db.get("key", durability_filter: "remote")

# Include uncommitted data
db.get("key", dirty: true)

# Control block caching
db.get("key", cache_blocks: false)
```

#### Delete Options

```ruby
# Don't wait for durability
db.delete("key", await_durable: false)
```

### Scanning

Iterate over key ranges using the `scan` method:

```ruby
# Scan all keys from "a" onwards
db.scan("a").each do |key, value|
  puts "#{key}: #{value}"
end

# Scan a specific range [start, end)
db.scan("a", "z").each do |key, value|
  puts "#{key}: #{value}"
end

# Use Enumerable methods
keys = db.scan("user:").map { |k, v| k }
users = db.scan("user:").select { |k, v| v.include?("active") }

# Convert to array
all_entries = db.scan("").to_a
```

### Write Batches

Perform multiple writes atomically:

```ruby
# Create a batch manually
batch = SlateDb::WriteBatch.new
batch.put("key1", "value1")
batch.put("key2", "value2", ttl: 60_000)
batch.delete("old_key")
db.write(batch)

# Or use the block helper
db.batch do |b|
  b.put("key1", "value1")
  b.put("key2", "value2")
  b.delete("old_key")
end
```

### Transactions

ACID transactions with snapshot or serializable isolation:

```ruby
# Block form (recommended) - auto-commits on success, rolls back on exception
db.transaction do |txn|
  balance = txn.get("balance").to_i
  txn.put("balance", (balance - 100).to_s)
  txn.put("withdrawal", "100")
end

# With serializable isolation for strict consistency
db.transaction(isolation: :serializable) do |txn|
  counter = txn.get("counter").to_i
  txn.put("counter", (counter + 1).to_s)
end

# Manual transaction management
txn = db.begin_transaction(isolation: :snapshot)
txn.put("key", "value")
txn.commit  # or txn.rollback
```

Transaction operations:

```ruby
db.transaction do |txn|
  # Read
  value = txn.get("key")
  
  # Write
  txn.put("key", "value")
  txn.put("expiring", "data", ttl: 30_000)
  
  # Delete
  txn.delete("old_key")
  
  # Scan
  txn.scan("prefix:").each do |k, v|
    puts "#{k}: #{v}"
  end
end
```

### Snapshots

Point-in-time consistent reads:

```ruby
# Block form (recommended)
db.snapshot do |snap|
  # All reads see the same consistent state
  value1 = snap.get("key1")
  value2 = snap.get("key2")
  
  snap.scan("prefix:").each do |k, v|
    puts "#{k}: #{v}"
  end
end  # automatically closed

# Manual management
snap = db.snapshot
value = snap.get("key")
snap.close
```

### Reader (Read-Only Access)

Open a database in read-only mode, useful for replicas:

```ruby
# Basic read-only access
SlateDb::Reader.open("/tmp/mydb", url: "s3://bucket/path") do |reader|
  value = reader.get("key")
  
  reader.scan("prefix:").each do |k, v|
    puts "#{k}: #{v}"
  end
end

# Open at a specific checkpoint
SlateDb::Reader.open("/tmp/mydb", 
                     url: "s3://bucket/path",
                     checkpoint_id: "uuid-here") do |reader|
  reader.get("key")
end
```

### Admin Operations

Administrative operations for database management:

```ruby
admin = SlateDb::Admin.new("/tmp/mydb", url: "s3://bucket/path")

# Manifests
json = admin.read_manifest           # Latest manifest as JSON
json = admin.read_manifest(123)      # Specific manifest by ID
json = admin.list_manifests          # List all manifests
json = admin.list_manifests(start: 1, end_id: 10)  # Range query

# Checkpoints
result = admin.create_checkpoint(name: "backup-2024")
# => { id: "uuid-string", manifest_id: 7 }

checkpoints = admin.list_checkpoints
checkpoints = admin.list_checkpoints(name: "backup")  # Filter by name

admin.refresh_checkpoint("uuid", lifetime: 3600_000)  # Extend lifetime
admin.delete_checkpoint("uuid")

# Garbage Collection
admin.run_gc                         # Run with default settings
admin.run_gc(min_age: 3600_000)      # Only collect objects older than 1 hour
```

### Flushing

Ensure all writes are persisted:

```ruby
db.put("key", "value")
db.flush
```

## Error Handling

SlateDB defines several exception classes:

```ruby
begin
  db.put("", "value")  # empty key
rescue SlateDb::InvalidArgumentError => e
  puts "Invalid argument: #{e.message}"
rescue SlateDb::TransactionError => e
  puts "Transaction conflict: #{e.message}"
rescue SlateDb::Error => e
  puts "SlateDB error: #{e.message}"
end
```

Exception hierarchy:

- `SlateDb::Error` - Base class (inherits from `StandardError`)
  - `SlateDb::TransactionError` - Transaction conflicts
  - `SlateDb::ClosedError` - Database has been closed
  - `SlateDb::UnavailableError` - Storage/network unavailable
  - `SlateDb::InvalidArgumentError` - Invalid arguments
  - `SlateDb::DataError` - Data corruption or format errors
  - `SlateDb::InternalError` - Internal errors

## Development

After checking out the repo, run:

```bash
cd slatedb-rb
bundle install
bundle exec rake compile
bundle exec rspec
```

To run specific tests:

```bash
bundle exec rspec spec/database_spec.rb
bundle exec rspec spec/transaction_spec.rb
```

## License

Apache-2.0
