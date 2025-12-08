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
cd ext/slatedb_ext && ruby extconf.rb && make && make install
bundle exec rspec
```

## Current Status

This is Milestone 1 (MVP) of the Ruby bindings, implementing:

- [x] Database open/close
- [x] Basic CRUD operations (get, put, delete)
- [x] Flush operation
- [x] Error handling
- [x] Block form for automatic cleanup

Future milestones will add:

- [ ] Iterator with Enumerable support
- [ ] WriteBatch for atomic batch writes
- [ ] Transactions
- [ ] Snapshots
- [ ] Reader (read-only access)
- [ ] Admin operations

## License

Apache-2.0
