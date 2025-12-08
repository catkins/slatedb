# SlateDB Ruby Bindings Implementation Plan

## Overview

This plan outlines the implementation of Ruby bindings for SlateDB using the [Magnus](https://github.com/matsadler/magnus) crate. The goal is to provide an **idiomatic Ruby API** that is **symmetrical with the Python and Go bindings** while leveraging Ruby's conventions.

## Key Design Decisions

### 1. Synchronous API (like Go bindings)

Unlike Python which offers both sync and async APIs, Ruby will follow the Go approach with a **synchronous-only API**:

- Ruby's async story (Fibers, async gem) is less mature than Python's asyncio
- Most Ruby applications are synchronous (Rails, etc.)
- Simpler implementation and easier to use
- Each `Db` instance will own a Tokio runtime and use `block_on()` internally

### 2. Idiomatic Ruby Patterns

| Pattern | Ruby Implementation |
|---------|-------------------|
| Constructor | `SlateDb.open(path, **options)` |
| Options | Keyword arguments with symbols |
| Nil handling | `nil` for missing values (not exceptions) |
| Iteration | `Enumerable` module, `each` with blocks |
| Resource cleanup | Block form with automatic cleanup |
| Naming | `snake_case` methods, `?` for predicates |

### 3. API Symmetry with Other Bindings

The Ruby bindings will expose the same core functionality as Python and Go:

| Feature | Python | Go | Ruby |
|---------|--------|-----|------|
| Database | `SlateDB` | `DB` | `SlateDb::Database` |
| Reader | `SlateDBReader` | `DbReader` | `SlateDb::Reader` |
| Snapshot | `SlateDBSnapshot` | - | `SlateDb::Snapshot` |
| Transaction | `SlateDBTransaction` | - | `SlateDb::Transaction` |
| WriteBatch | `WriteBatch` | `WriteBatch` | `SlateDb::WriteBatch` |
| Iterator | `DbIterator` | `Iterator` | `SlateDb::Iterator` (+ Enumerable) |
| Admin | `SlateDBAdmin` | - | `SlateDb::Admin` |

---

## Project Structure

```
slatedb-rb/
├── Cargo.toml                 # Rust crate configuration
├── Gemfile                    # Ruby development dependencies
├── Rakefile                   # Build tasks
├── slatedb.gemspec           # Gem specification
├── lib/
│   └── slatedb/
│       ├── version.rb        # Gem version
│       └── slatedb.rb        # Ruby wrapper/loader
├── ext/
│   └── slatedb/
│       ├── Cargo.toml        # Extension crate
│       ├── extconf.rb        # Extension configuration
│       └── src/
│           ├── lib.rs        # Main entry point
│           ├── database.rs   # Database wrapper
│           ├── reader.rs     # Reader wrapper
│           ├── snapshot.rs   # Snapshot wrapper
│           ├── transaction.rs # Transaction wrapper
│           ├── write_batch.rs # WriteBatch wrapper
│           ├── iterator.rs   # Iterator wrapper
│           ├── admin.rs      # Admin wrapper
│           ├── errors.rs     # Error handling
│           ├── options.rs    # Options conversion
│           └── runtime.rs    # Tokio runtime management
├── sig/
│   └── slatedb.rbs           # RBS type signatures
└── spec/
    ├── spec_helper.rb
    ├── database_spec.rb
    ├── reader_spec.rb
    ├── snapshot_spec.rb
    ├── transaction_spec.rb
    ├── write_batch_spec.rb
    └── iterator_spec.rb
```

---

## Phase 1: Project Setup

### 1.1 Cargo.toml (root)

```toml
[workspace]
members = ["ext/slatedb"]

[workspace.dependencies]
slatedb = { path = "../" }
```

### 1.2 ext/slatedb/Cargo.toml

```toml
[package]
name = "slatedb-ruby"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
name = "slatedb"

[dependencies]
slatedb = { workspace = true }
magnus = "0.7"
tokio = { version = "1", features = ["rt-multi-thread"] }
bytes = "1"
object_store = { version = "0.11", features = ["aws"] }
once_cell = "1"
```

### 1.3 ext/slatedb/extconf.rb

```ruby
require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("slatedb/slatedb")
```

### 1.4 slatedb.gemspec

```ruby
Gem::Specification.new do |spec|
  spec.name          = "slatedb"
  spec.version       = SlateDb::VERSION
  spec.authors       = ["SlateDB Contributors"]
  spec.summary       = "Ruby bindings for SlateDB"
  spec.description   = "A cloud-native embedded key-value store"
  
  spec.files         = Dir["lib/**/*.rb", "ext/**/*.rs", "ext/**/Cargo.toml", "ext/**/extconf.rb"]
  spec.extensions    = ["ext/slatedb/extconf.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rb_sys", "~> 0.9"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.12"
end
```

---

## Phase 2: Core Types Implementation

### 2.1 Runtime Management (runtime.rs)

```rust
use once_cell::sync::OnceCell;
use tokio::runtime::Runtime;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();

pub fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Runtime::new().expect("Failed to create Tokio runtime")
    })
}
```

### 2.2 Error Handling (errors.rs)

Map SlateDB errors to Ruby exceptions:

| SlateDB ErrorKind | Ruby Exception |
|------------------|----------------|
| `Transaction` | `SlateDb::TransactionError` |
| `Closed` | `SlateDb::ClosedError` |
| `Unavailable` | `SlateDb::UnavailableError` |
| `Invalid` | `SlateDb::InvalidArgumentError` |
| `Data` | `SlateDb::DataError` |
| `Internal` | `SlateDb::InternalError` |

```rust
use magnus::{Error, Ruby, ExceptionClass};

pub fn define_exceptions(ruby: &Ruby, module: &magnus::RModule) -> Result<(), Error> {
    let slate_error = module.define_class("Error", ruby.exception_standard_error())?;
    module.define_class("TransactionError", slate_error)?;
    module.define_class("ClosedError", slate_error)?;
    module.define_class("UnavailableError", slate_error)?;
    module.define_class("InvalidArgumentError", slate_error)?;
    module.define_class("DataError", slate_error)?;
    module.define_class("InternalError", slate_error)?;
    Ok(())
}

pub fn map_error(ruby: &Ruby, err: slatedb::Error) -> Error {
    let msg = format!("{}", err);
    match err.kind() {
        slatedb::ErrorKind::Transaction => Error::new(get_exception(ruby, "TransactionError"), msg),
        slatedb::ErrorKind::Closed(_) => Error::new(get_exception(ruby, "ClosedError"), msg),
        slatedb::ErrorKind::Unavailable => Error::new(get_exception(ruby, "UnavailableError"), msg),
        slatedb::ErrorKind::Invalid => Error::new(get_exception(ruby, "InvalidArgumentError"), msg),
        slatedb::ErrorKind::Data => Error::new(get_exception(ruby, "DataError"), msg),
        slatedb::ErrorKind::Internal => Error::new(get_exception(ruby, "InternalError"), msg),
    }
}
```

### 2.3 Options Conversion (options.rs)

Convert Ruby keyword arguments to Rust options structs:

```rust
use magnus::{RHash, Symbol, TryConvert, Value};

pub fn parse_read_options(ruby: &Ruby, opts: Option<RHash>) -> Result<ReadOptions, Error> {
    let mut read_opts = ReadOptions::default();
    
    if let Some(hash) = opts {
        if let Some(val) = hash.get(Symbol::new("durability_filter")) {
            read_opts.durability_filter = parse_durability_level(ruby, val)?;
        }
        if let Some(val) = hash.get(Symbol::new("dirty")) {
            read_opts.dirty = bool::try_convert(val)?;
        }
        if let Some(val) = hash.get(Symbol::new("cache_blocks")) {
            read_opts.cache_blocks = bool::try_convert(val)?;
        }
    }
    
    Ok(read_opts)
}
```

---

## Phase 3: Database Class (database.rs)

### Ruby API Design

```ruby
# Opening a database
db = SlateDb::Database.open("/tmp/mydb")
db = SlateDb::Database.open("/tmp/mydb", url: "s3://bucket/path")
db = SlateDb::Database.open("/tmp/mydb") do |db|
  # Auto-closed when block exits
end

# Basic operations
db.put("key", "value")
db.get("key")           # => "value" or nil
db.delete("key")

# With options
db.put("key", "value", ttl: 3600_000, await_durable: false)
db.get("key", durability_filter: :memory, dirty: true)

# Scanning
db.scan("a", "z")                    # => Iterator
db.scan("prefix").each { |k, v| ... }
db.scan("a", "z").to_a               # => [[key, value], ...]

# Transactions
db.transaction do |txn|
  val = txn.get("counter")
  txn.put("counter", val.to_i + 1)
end # Auto-commits

# Or manual control
txn = db.begin_transaction(isolation: :serializable)
txn.put("key", "value")
txn.commit

# Snapshots
snapshot = db.snapshot
snapshot.get("key")
snapshot.scan("a", "z")
snapshot.close

# Batch writes
batch = SlateDb::WriteBatch.new
batch.put("key1", "value1")
batch.put("key2", "value2", ttl: 60_000)
batch.delete("key3")
db.write(batch)

# Lifecycle
db.flush
db.close
```

### Rust Implementation

```rust
use std::sync::Arc;
use magnus::{function, method, prelude::*, Error, Ruby, RHash, RString};
use slatedb::Db;

#[magnus::wrap(class = "SlateDb::Database")]
struct Database {
    inner: Arc<Db>,
}

impl Database {
    fn open(ruby: &Ruby, path: String, kwargs: RHash) -> Result<Self, Error> {
        let rt = get_runtime();
        let url = kwargs.get(Symbol::new("url"));
        
        let db = rt.block_on(async {
            // Build object store from URL or local path
            let object_store = resolve_object_store(&path, url)?;
            Db::open(path, object_store).await
        }).map_err(|e| map_error(ruby, e))?;
        
        Ok(Self { inner: Arc::new(db) })
    }
    
    fn get(&self, ruby: &Ruby, key: RString, kwargs: Option<RHash>) -> Result<Option<Vec<u8>>, Error> {
        let key_bytes = unsafe { key.as_slice() };
        if key_bytes.is_empty() {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "key cannot be empty"
            ));
        }
        
        let opts = parse_read_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        rt.block_on(async {
            self.inner.get_with_options(key_bytes, &opts).await
        })
        .map(|opt| opt.map(|b| b.to_vec()))
        .map_err(|e| map_error(ruby, e))
    }
    
    fn put(&self, ruby: &Ruby, key: RString, value: RString, kwargs: Option<RHash>) -> Result<(), Error> {
        let key_bytes = unsafe { key.as_slice() };
        let value_bytes = unsafe { value.as_slice() };
        
        if key_bytes.is_empty() {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "key cannot be empty"
            ));
        }
        
        let (put_opts, write_opts) = parse_put_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        rt.block_on(async {
            self.inner.put_with_options(key_bytes, value_bytes, &put_opts).await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn delete(&self, ruby: &Ruby, key: RString, kwargs: Option<RHash>) -> Result<(), Error> {
        let key_bytes = unsafe { key.as_slice() };
        let opts = parse_write_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        rt.block_on(async {
            self.inner.delete_with_options(key_bytes, &opts).await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn scan(&self, ruby: &Ruby, start: RString, end_key: Option<RString>, kwargs: Option<RHash>) 
        -> Result<Iterator, Error> 
    {
        let opts = parse_scan_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        let iter = rt.block_on(async {
            let range = build_range(start, end_key);
            self.inner.scan_with_options(range, &opts).await
        }).map_err(|e| map_error(ruby, e))?;
        
        Ok(Iterator::new(iter))
    }
    
    fn begin_transaction(&self, ruby: &Ruby, kwargs: Option<RHash>) -> Result<Transaction, Error> {
        let isolation = parse_isolation_level(ruby, kwargs)?;
        let rt = get_runtime();
        
        let txn = rt.block_on(async {
            self.inner.begin(isolation).await
        }).map_err(|e| map_error(ruby, e))?;
        
        Ok(Transaction::new(txn))
    }
    
    fn snapshot(&self, ruby: &Ruby) -> Result<Snapshot, Error> {
        let rt = get_runtime();
        
        let snap = rt.block_on(async {
            self.inner.snapshot().await
        }).map_err(|e| map_error(ruby, e))?;
        
        Ok(Snapshot::new(snap))
    }
    
    fn write(&self, ruby: &Ruby, batch: &WriteBatch, kwargs: Option<RHash>) -> Result<(), Error> {
        let opts = parse_write_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        let batch_inner = batch.take()?;
        rt.block_on(async {
            self.inner.write_with_options(batch_inner, &opts).await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn flush(&self, ruby: &Ruby, kwargs: Option<RHash>) -> Result<(), Error> {
        let rt = get_runtime();
        // Parse flush_type from kwargs if present
        rt.block_on(async {
            self.inner.flush().await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn close(&self, ruby: &Ruby) -> Result<(), Error> {
        let rt = get_runtime();
        rt.block_on(async {
            self.inner.close().await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn metrics(&self) -> RHash {
        // Convert metrics registry to Ruby hash
    }
}
```

---

## Phase 4: Iterator with Enumerable (iterator.rs)

Ruby iterators should integrate with `Enumerable`:

```rust
use std::cell::RefCell;

#[magnus::wrap(class = "SlateDb::Iterator")]
struct Iterator {
    inner: RefCell<Option<DbIterator>>,
}

impl Iterator {
    fn new(iter: DbIterator) -> Self {
        Self { inner: RefCell::new(Some(iter)) }
    }
    
    fn next(&self, ruby: &Ruby) -> Result<Option<(Vec<u8>, Vec<u8>)>, Error> {
        let mut guard = self.inner.borrow_mut();
        let iter = guard.as_mut().ok_or_else(|| {
            Error::new(ruby.exception_standard_error(), "iterator closed")
        })?;
        
        let rt = get_runtime();
        rt.block_on(async {
            iter.next().await
        })
        .map(|opt| opt.map(|kv| (kv.key.to_vec(), kv.value.to_vec())))
        .map_err(|e| map_error(ruby, e))
    }
    
    fn seek(&self, ruby: &Ruby, key: RString) -> Result<(), Error> {
        let key_bytes = unsafe { key.as_slice() };
        let mut guard = self.inner.borrow_mut();
        let iter = guard.as_mut().ok_or_else(|| {
            Error::new(ruby.exception_standard_error(), "iterator closed")
        })?;
        
        let rt = get_runtime();
        rt.block_on(async {
            iter.seek(key_bytes).await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn each(&self, ruby: &Ruby) -> Result<magnus::Value, Error> {
        // Yields each [key, value] pair to the block
        // Returns self to support chaining
    }
    
    fn close(&self) -> Result<(), Error> {
        *self.inner.borrow_mut() = None;
        Ok(())
    }
}
```

Ruby wrapper to include Enumerable:

```ruby
# lib/slatedb/slatedb.rb
module SlateDb
  class Iterator
    include Enumerable
    
    # `each` is implemented in Rust
    # Enumerable provides: map, select, find, to_a, etc.
  end
end
```

---

## Phase 5: Transaction (transaction.rs)

```rust
#[magnus::wrap(class = "SlateDb::Transaction")]
struct Transaction {
    inner: RefCell<Option<DBTransaction>>,
}

impl Transaction {
    fn get(&self, ruby: &Ruby, key: RString, kwargs: Option<RHash>) -> Result<Option<Vec<u8>>, Error> {
        // Similar to Database::get but on transaction
    }
    
    fn put(&self, ruby: &Ruby, key: RString, value: RString, kwargs: Option<RHash>) -> Result<(), Error> {
        // Buffered write (synchronous, no await needed)
    }
    
    fn delete(&self, ruby: &Ruby, key: RString) -> Result<(), Error> {
        // Buffered delete
    }
    
    fn commit(&self, ruby: &Ruby, kwargs: Option<RHash>) -> Result<(), Error> {
        let txn = self.inner.borrow_mut().take().ok_or_else(|| {
            Error::new(ruby.exception_standard_error(), "transaction already committed or rolled back")
        })?;
        
        let opts = parse_write_options(ruby, kwargs)?;
        let rt = get_runtime();
        
        rt.block_on(async {
            txn.commit_with_options(&opts).await
        }).map_err(|e| map_error(ruby, e))
    }
    
    fn rollback(&self, ruby: &Ruby) -> Result<(), Error> {
        self.inner.borrow_mut().take();
        Ok(())
    }
}
```

Ruby block-based transaction helper:

```ruby
# lib/slatedb/slatedb.rb
module SlateDb
  class Database
    def transaction(isolation: :snapshot)
      txn = begin_transaction(isolation: isolation)
      yield txn
      txn.commit
    rescue => e
      txn.rollback rescue nil
      raise
    end
  end
end
```

---

## Phase 6: WriteBatch (write_batch.rs)

```rust
#[magnus::wrap(class = "SlateDb::WriteBatch")]
struct WriteBatch {
    inner: RefCell<Option<slatedb::WriteBatch>>,
}

impl WriteBatch {
    fn new() -> Self {
        Self { inner: RefCell::new(Some(slatedb::WriteBatch::new())) }
    }
    
    fn put(&self, ruby: &Ruby, key: RString, value: RString, kwargs: Option<RHash>) -> Result<&Self, Error> {
        // Add put operation to batch
        // Returns self for chaining
    }
    
    fn delete(&self, ruby: &Ruby, key: RString) -> Result<&Self, Error> {
        // Add delete operation to batch
        // Returns self for chaining
    }
    
    fn merge(&self, ruby: &Ruby, key: RString, value: RString, kwargs: Option<RHash>) -> Result<&Self, Error> {
        // Add merge operation to batch
    }
    
    // Internal: consume the batch (called by Database::write)
    fn take(&self) -> Result<slatedb::WriteBatch, Error> {
        self.inner.borrow_mut().take().ok_or_else(|| {
            Error::new(ruby.exception_standard_error(), "batch already consumed")
        })
    }
}
```

---

## Phase 7: Snapshot (snapshot.rs)

```rust
#[magnus::wrap(class = "SlateDb::Snapshot")]
struct Snapshot {
    inner: RefCell<Option<Arc<DbSnapshot>>>,
}

impl Snapshot {
    fn get(&self, ruby: &Ruby, key: RString, kwargs: Option<RHash>) -> Result<Option<Vec<u8>>, Error> {
        // Read from snapshot
    }
    
    fn scan(&self, ruby: &Ruby, start: RString, end_key: Option<RString>, kwargs: Option<RHash>) 
        -> Result<Iterator, Error> 
    {
        // Scan from snapshot
    }
    
    fn close(&self) -> Result<(), Error> {
        *self.inner.borrow_mut() = None;
        Ok(())
    }
}
```

---

## Phase 8: Reader (reader.rs)

For read-only access (e.g., from replicas):

```rust
#[magnus::wrap(class = "SlateDb::Reader")]
struct Reader {
    inner: Arc<Db>, // Opened in read-only mode
}

impl Reader {
    fn open(ruby: &Ruby, path: String, kwargs: RHash) -> Result<Self, Error> {
        // Similar to Database::open but read-only
    }
    
    fn get(&self, ruby: &Ruby, key: RString, kwargs: Option<RHash>) -> Result<Option<Vec<u8>>, Error> {
        // Read operation
    }
    
    fn scan(&self, ruby: &Ruby, start: RString, end_key: Option<RString>, kwargs: Option<RHash>) 
        -> Result<Iterator, Error> 
    {
        // Scan operation
    }
    
    fn close(&self, ruby: &Ruby) -> Result<(), Error> {
        // Close reader
    }
}
```

---

## Phase 9: Admin (admin.rs)

```rust
#[magnus::wrap(class = "SlateDb::Admin")]
struct Admin {
    inner: slatedb::Admin,
}

impl Admin {
    fn new(ruby: &Ruby, path: String, kwargs: RHash) -> Result<Self, Error> {
        // Initialize admin
    }
    
    fn read_manifest(&self, ruby: &Ruby, id: Option<u64>) -> Result<Option<String>, Error> {
        // Returns JSON string
    }
    
    fn list_manifests(&self, ruby: &Ruby, start: Option<u64>, end_id: Option<u64>) -> Result<String, Error> {
        // Returns JSON string
    }
    
    fn create_checkpoint(&self, ruby: &Ruby, kwargs: RHash) -> Result<RHash, Error> {
        // Returns { id: "...", manifest_id: ... }
    }
    
    fn list_checkpoints(&self, ruby: &Ruby, name: Option<String>) -> Result<Vec<RHash>, Error> {
        // Returns array of checkpoint hashes
    }
    
    fn run_gc(&self, ruby: &Ruby, kwargs: RHash) -> Result<(), Error> {
        // Run garbage collection
    }
}
```

---

## Phase 10: Module Initialization (lib.rs)

```rust
use magnus::{define_module, function, method, prelude::*, Error, Ruby};

mod database;
mod reader;
mod snapshot;
mod transaction;
mod write_batch;
mod iterator;
mod admin;
mod errors;
mod options;
mod runtime;

use database::Database;
use reader::Reader;
use snapshot::Snapshot;
use transaction::Transaction;
use write_batch::WriteBatch;
use iterator::Iterator;
use admin::Admin;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("SlateDb")?;
    
    // Define exception classes
    errors::define_exceptions(ruby, &module)?;
    
    // Database class
    let db_class = module.define_class("Database", ruby.class_object())?;
    db_class.define_singleton_method("open", function!(Database::open, -1))?;
    db_class.define_method("get", method!(Database::get, -1))?;
    db_class.define_method("put", method!(Database::put, -1))?;
    db_class.define_method("delete", method!(Database::delete, -1))?;
    db_class.define_method("scan", method!(Database::scan, -1))?;
    db_class.define_method("begin_transaction", method!(Database::begin_transaction, -1))?;
    db_class.define_method("snapshot", method!(Database::snapshot, 0))?;
    db_class.define_method("write", method!(Database::write, -1))?;
    db_class.define_method("flush", method!(Database::flush, -1))?;
    db_class.define_method("close", method!(Database::close, 0))?;
    db_class.define_method("metrics", method!(Database::metrics, 0))?;
    
    // Reader class
    let reader_class = module.define_class("Reader", ruby.class_object())?;
    reader_class.define_singleton_method("open", function!(Reader::open, -1))?;
    reader_class.define_method("get", method!(Reader::get, -1))?;
    reader_class.define_method("scan", method!(Reader::scan, -1))?;
    reader_class.define_method("close", method!(Reader::close, 0))?;
    
    // Snapshot class
    let snapshot_class = module.define_class("Snapshot", ruby.class_object())?;
    snapshot_class.define_method("get", method!(Snapshot::get, -1))?;
    snapshot_class.define_method("scan", method!(Snapshot::scan, -1))?;
    snapshot_class.define_method("close", method!(Snapshot::close, 0))?;
    
    // Transaction class
    let txn_class = module.define_class("Transaction", ruby.class_object())?;
    txn_class.define_method("get", method!(Transaction::get, -1))?;
    txn_class.define_method("put", method!(Transaction::put, -1))?;
    txn_class.define_method("delete", method!(Transaction::delete, 1))?;
    txn_class.define_method("scan", method!(Transaction::scan, -1))?;
    txn_class.define_method("commit", method!(Transaction::commit, -1))?;
    txn_class.define_method("rollback", method!(Transaction::rollback, 0))?;
    
    // WriteBatch class
    let batch_class = module.define_class("WriteBatch", ruby.class_object())?;
    batch_class.define_singleton_method("new", function!(WriteBatch::new, 0))?;
    batch_class.define_method("put", method!(WriteBatch::put, -1))?;
    batch_class.define_method("delete", method!(WriteBatch::delete, 1))?;
    batch_class.define_method("merge", method!(WriteBatch::merge, -1))?;
    
    // Iterator class
    let iter_class = module.define_class("Iterator", ruby.class_object())?;
    iter_class.define_method("next", method!(Iterator::next, 0))?;
    iter_class.define_method("seek", method!(Iterator::seek, 1))?;
    iter_class.define_method("each", method!(Iterator::each, 0))?;
    iter_class.define_method("close", method!(Iterator::close, 0))?;
    
    // Admin class
    let admin_class = module.define_class("Admin", ruby.class_object())?;
    admin_class.define_singleton_method("new", function!(Admin::new, -1))?;
    admin_class.define_method("read_manifest", method!(Admin::read_manifest, -1))?;
    admin_class.define_method("list_manifests", method!(Admin::list_manifests, -1))?;
    admin_class.define_method("create_checkpoint", method!(Admin::create_checkpoint, -1))?;
    admin_class.define_method("list_checkpoints", method!(Admin::list_checkpoints, -1))?;
    admin_class.define_method("run_gc", method!(Admin::run_gc, -1))?;
    
    Ok(())
}
```

---

## Phase 11: Ruby Wrapper (lib/slatedb/slatedb.rb)

```ruby
require_relative "slatedb/version"
require_relative "slatedb/slatedb.so" # Native extension

module SlateDb
  class Iterator
    include Enumerable
  end
  
  class Database
    # Block form with automatic cleanup
    def self.open(path, **options, &block)
      db = _open(path, **options)
      return db unless block_given?
      
      begin
        yield db
      ensure
        db.close rescue nil
      end
    end
    
    # Block-based transaction helper
    def transaction(isolation: :snapshot)
      txn = begin_transaction(isolation: isolation)
      result = yield txn
      txn.commit
      result
    rescue => e
      txn.rollback rescue nil
      raise
    end
  end
  
  class Snapshot
    def self.open(...)
      snapshot = _open(...)
      return snapshot unless block_given?
      
      begin
        yield snapshot
      ensure
        snapshot.close rescue nil
      end
    end
  end
  
  class Reader
    def self.open(...)
      reader = _open(...)
      return reader unless block_given?
      
      begin
        yield reader
      ensure
        reader.close rescue nil
      end
    end
  end
end
```

---

## Phase 12: RBS Type Signatures (sig/slatedb.rbs)

```rbs
module SlateDb
  VERSION: String
  
  class Error < StandardError
  end
  
  class TransactionError < Error
  end
  
  class ClosedError < Error
  end
  
  class UnavailableError < Error
  end
  
  class InvalidArgumentError < Error
  end
  
  class DataError < Error
  end
  
  class InternalError < Error
  end
  
  class Database
    def self.open: (String path, ?url: String?, ?env_file: String?, ?settings: Hash[Symbol, untyped]?) -> Database
                 | (String path, ?url: String?, ?env_file: String?, ?settings: Hash[Symbol, untyped]?) { (Database) -> void } -> void
    
    def get: (String key, ?durability_filter: Symbol?, ?dirty: bool?, ?cache_blocks: bool?) -> String?
    def put: (String key, String value, ?ttl: Integer?, ?await_durable: bool?) -> void
    def delete: (String key, ?await_durable: bool?) -> void
    def scan: (String start, ?String? end_key, ?durability_filter: Symbol?, ?dirty: bool?, ?read_ahead_bytes: Integer?, ?cache_blocks: bool?, ?max_fetch_tasks: Integer?) -> Iterator
    def begin_transaction: (?isolation: Symbol?) -> Transaction
    def transaction: (?isolation: Symbol?) { (Transaction) -> untyped } -> untyped
    def snapshot: () -> Snapshot
    def write: (WriteBatch batch, ?await_durable: bool?) -> void
    def flush: (?flush_type: Symbol?) -> void
    def close: () -> void
    def metrics: () -> Hash[Symbol, untyped]
  end
  
  class Iterator
    include Enumerable[[String, String]]
    
    def next: () -> [String, String]?
    def seek: (String key) -> void
    def each: () { ([String, String]) -> void } -> self
           | () -> Enumerator[[String, String], self]
    def close: () -> void
  end
  
  class Transaction
    def get: (String key, ?durability_filter: Symbol?, ?dirty: bool?, ?cache_blocks: bool?) -> String?
    def put: (String key, String value, ?ttl: Integer?) -> void
    def delete: (String key) -> void
    def scan: (String start, ?String? end_key, ?durability_filter: Symbol?, ?dirty: bool?) -> Iterator
    def commit: (?await_durable: bool?) -> void
    def rollback: () -> void
  end
  
  class Snapshot
    def get: (String key, ?durability_filter: Symbol?, ?dirty: bool?, ?cache_blocks: bool?) -> String?
    def scan: (String start, ?String? end_key, ?durability_filter: Symbol?, ?dirty: bool?) -> Iterator
    def close: () -> void
  end
  
  class WriteBatch
    def self.new: () -> WriteBatch
    def put: (String key, String value, ?ttl: Integer?) -> self
    def delete: (String key) -> self
    def merge: (String key, String value, ?ttl: Integer?) -> self
  end
  
  class Reader
    def self.open: (String path, ?url: String?, ?checkpoint_id: String?, ?manifest_poll_interval: Integer?, ?checkpoint_lifetime: Integer?, ?max_memtable_bytes: Integer?) -> Reader
                 | (String path, ?url: String?, ?checkpoint_id: String?) { (Reader) -> void } -> void
    
    def get: (String key, ?durability_filter: Symbol?, ?dirty: bool?, ?cache_blocks: bool?) -> String?
    def scan: (String start, ?String? end_key, ?durability_filter: Symbol?, ?dirty: bool?) -> Iterator
    def close: () -> void
  end
  
  class Admin
    def self.new: (String path, ?url: String?, ?env_file: String?, ?wal_url: String?) -> Admin
    
    def read_manifest: (?Integer? id) -> String?
    def list_manifests: (?start: Integer?, ?end_id: Integer?) -> String
    def create_checkpoint: (?lifetime: Integer?, ?source: String?, ?name: String?) -> Hash[Symbol, untyped]
    def list_checkpoints: (?name: String?) -> Array[Hash[Symbol, untyped]]
    def run_gc: (**untyped) -> void
  end
end
```

---

## Implementation Order

### Milestone 1: MVP (Core CRUD)
1. Project setup (Cargo.toml, gemspec, extconf.rb)
2. Runtime management
3. Error handling
4. Database class with basic operations (open, get, put, delete, close)
5. Basic tests

### Milestone 2: Iteration & Batch
1. Iterator class with Enumerable
2. WriteBatch class
3. Scan operations
4. Tests for iteration

### Milestone 3: Transactions & Snapshots
1. Transaction class
2. Snapshot class
3. Block-based transaction helper
4. Tests for transactions

### Milestone 4: Reader & Admin
1. Reader class
2. Admin class
3. Checkpoint operations
4. GC operations

### Milestone 5: Polish
1. RBS type signatures
2. Documentation
3. CI/CD setup
4. Performance benchmarks
5. Gem release preparation

---

## Testing Strategy

Use RSpec with similar patterns to Go's Ginkgo tests:

```ruby
# spec/database_spec.rb
RSpec.describe SlateDb::Database do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(tmpdir) }
  
  describe ".open" do
    it "opens a database at the given path" do
      db = SlateDb::Database.open(tmpdir)
      expect(db).to be_a(SlateDb::Database)
      db.close
    end
    
    it "yields to block and auto-closes" do
      opened = nil
      SlateDb::Database.open(tmpdir) do |db|
        opened = db
        db.put("key", "value")
      end
      # db should be closed now
    end
  end
  
  describe "#put and #get" do
    it "stores and retrieves values" do
      SlateDb::Database.open(tmpdir) do |db|
        db.put("hello", "world")
        expect(db.get("hello")).to eq("world")
      end
    end
    
    it "returns nil for missing keys" do
      SlateDb::Database.open(tmpdir) do |db|
        expect(db.get("nonexistent")).to be_nil
      end
    end
    
    it "raises InvalidArgumentError for empty keys" do
      SlateDb::Database.open(tmpdir) do |db|
        expect { db.put("", "value") }.to raise_error(SlateDb::InvalidArgumentError)
      end
    end
  end
  
  describe "#scan" do
    it "iterates over key range" do
      SlateDb::Database.open(tmpdir) do |db|
        db.put("a", "1")
        db.put("b", "2")
        db.put("c", "3")
        
        results = db.scan("a", "c").to_a
        expect(results).to eq([["a", "1"], ["b", "2"]])
      end
    end
    
    it "supports Enumerable methods" do
      SlateDb::Database.open(tmpdir) do |db|
        db.put("a", "1")
        db.put("b", "2")
        
        keys = db.scan("a").map { |k, v| k }
        expect(keys).to eq(["a", "b"])
      end
    end
  end
  
  describe "#transaction" do
    it "commits on success" do
      SlateDb::Database.open(tmpdir) do |db|
        db.transaction do |txn|
          txn.put("key", "value")
        end
        expect(db.get("key")).to eq("value")
      end
    end
    
    it "rolls back on exception" do
      SlateDb::Database.open(tmpdir) do |db|
        expect {
          db.transaction do |txn|
            txn.put("key", "value")
            raise "oops"
          end
        }.to raise_error("oops")
        
        expect(db.get("key")).to be_nil
      end
    end
  end
end
```

---

## Notes on Ruby Idioms

1. **Block forms**: Ruby developers expect `open` methods to accept blocks for automatic cleanup
2. **Keyword arguments**: Use `**kwargs` instead of option hashes where possible
3. **Enumerable**: Include this in Iterator for `map`, `select`, `to_a`, etc.
4. **Nil over exceptions**: Return `nil` for missing keys, not `KeyNotFoundError`
5. **Method chaining**: `WriteBatch#put` should return `self` for chaining
6. **Predicate methods**: Use `?` suffix for boolean methods (e.g., `closed?`)
7. **Bang methods**: Consider `flush!` for destructive/dangerous operations

---

## Differences from Python/Go Bindings

| Aspect | Python | Go | Ruby |
|--------|--------|-----|------|
| Async | Dual sync/async | Sync only | Sync only |
| Options | kwargs | Functional options | kwargs |
| Iteration | `__iter__`/`__aiter__` | `Next()`/`io.EOF` | `Enumerable#each` |
| Resource cleanup | Explicit `close()` | `defer Close()` | Block form |
| Errors | Custom exceptions | Sentinel errors | Custom exceptions |
| Type hints | `.pyi` stubs | Built-in | `.rbs` signatures |

---

## References

### SlateDB Core Rust API

| File | Description |
|------|-------------|
| `src/db.rs` | Main `Db` struct and core operations (get, put, delete, scan, flush, close) |
| `src/db_state.rs` | Database state management |
| `src/transaction.rs` | `DBTransaction` struct for ACID transactions |
| `src/snapshot.rs` | `DbSnapshot` for point-in-time consistent reads |
| `src/batch.rs` | `WriteBatch` for atomic batch writes |
| `src/iter.rs` | `DbIterator` for range scans |
| `src/config.rs` | `Settings`, `DbOptions`, and configuration types |
| `src/error.rs` | `Error` and `ErrorKind` definitions |
| `src/types.rs` | Core types like `KeyValue`, `Ttl`, `IsolationLevel` |
| `src/reader.rs` | Read-only database access |
| `src/admin.rs` | Administrative operations (manifests, checkpoints, GC) |
| `src/merge.rs` | `MergeOperator` trait for custom merge operations |

### Python Bindings (Reference Implementation)

| File | Description |
|------|-------------|
| `slatedb-py/src/lib.rs` | Main PyO3 bindings (~2,500 lines) - comprehensive reference for all wrapped types |
| `slatedb-py/python/slatedb/slatedb.pyi` | Type stubs showing complete public API surface |
| `slatedb-py/pyproject.toml` | Build configuration with maturin |
| `slatedb-py/Cargo.toml` | Rust dependencies for Python bindings |

**Key patterns to study:**
- GIL management with `py.allow_threads()` for blocking operations
- Dual sync/async API with `future_into_py()` for async methods
- Error mapping from `slatedb::Error` to Python exceptions
- Options parsing from Python kwargs to Rust structs
- Merge operator bridging (Python callable → Rust trait)
- Iterator implementation with `__iter__`/`__next__` and `__aiter__`/`__anext__`

### Go Bindings (Reference Implementation)

| File | Description |
|------|-------------|
| `slatedb-go/src/lib.rs` | Rust FFI layer with C-compatible exports |
| `slatedb-go/src/handle.rs` | Type-safe handle wrappers (`CSdbHandle`, `CSdbReaderHandle`) |
| `slatedb-go/src/error.rs` | C-compatible error codes and result types |
| `slatedb-go/go/db.go` | Go `DB` struct and methods |
| `slatedb-go/go/reader.go` | Go `DbReader` for read-only access |
| `slatedb-go/go/iterator.go` | Go `Iterator` with `Next()`/`io.EOF` pattern |
| `slatedb-go/go/batch.go` | Go `WriteBatch` implementation |
| `slatedb-go/go/options.go` | Functional options pattern (`WithUrl`, `WithSettings`) |
| `slatedb-go/go/settings.go` | Settings structs and JSON serialization |
| `slatedb-go/go/errors.go` | Sentinel errors (`ErrNotFound`, `ErrInvalidArgument`) |
| `slatedb-go/build.rs` | cbindgen configuration for C header generation |

**Key patterns to study:**
- Per-database Tokio runtime with `block_on()` for sync API
- CGO pointer management and memory safety
- Settings serialization via JSON roundtrip
- Builder pattern for database configuration
- Iterator state tracking with closed/consumed flags

### Magnus (Ruby-Rust Bindings)

| Resource | URL |
|----------|-----|
| GitHub Repository | https://github.com/matsadler/magnus |
| Documentation | https://docs.rs/magnus |
| rb_sys (build tooling) | https://github.com/oxidize-rb/rb-sys |

**Key Magnus patterns:**
- `#[magnus::wrap(class = "...")]` for wrapping Rust structs as Ruby objects
- `#[magnus::init]` for module initialization
- `function!()` macro for class methods, `method!()` for instance methods
- `RefCell` for interior mutability in wrapped types
- Error handling with `magnus::Error` and custom exception classes
- Type conversions between Ruby and Rust types
- Keyword argument handling with `RHash` and `Symbol`

### Ruby Extension Development

| Resource | Description |
|----------|-------------|
| [rb_sys README](https://github.com/oxidize-rb/rb-sys) | Build tooling for Rust Ruby extensions |
| [rake-compiler](https://github.com/rake-compiler/rake-compiler) | Ruby extension build automation |
| [RBS](https://github.com/ruby/rbs) | Ruby type signature format |
| [Bundler gem development](https://bundler.io/guides/creating_gem.html) | Standard gem structure |

### Example Ruby Gems with Rust Extensions

These gems use Magnus and can serve as additional references:

| Gem | Repository | Notes |
|-----|------------|-------|
| `polars-ruby` | https://github.com/ankane/polars-ruby | Data frame library, complex types |
| `fast_excel` | https://github.com/Paxa/fast_excel | File I/O patterns |
| `rust_json_schema` | https://github.com/driv3r/rust_json_schema | Simple API, good starter reference |

### Build & Distribution

| Topic | Reference |
|-------|-----------|
| Cross-compilation | https://github.com/oxidize-rb/rb-sys#cross-compilation |
| GitHub Actions CI | https://github.com/oxidize-rb/actions |
| Publishing to RubyGems | https://guides.rubygems.org/publishing/ |

### Testing

| Tool | Purpose |
|------|---------|
| RSpec | BDD testing framework for Ruby |
| Minitest | Alternative lightweight testing |
| SimpleCov | Code coverage reporting |

---

## Quick Start Commands

```bash
# Create gem structure
bundle gem slatedb --ext=rust

# Build native extension
bundle exec rake compile

# Run tests
bundle exec rspec

# Build gem
gem build slatedb.gemspec

# Install locally
gem install slatedb-*.gem
```
