//! SlateDB Ruby bindings
//!
//! This crate provides Ruby bindings for SlateDB, a cloud-native embedded
//! key-value store built on object storage.
//!
//! # Example
//!
//! ```ruby
//! require 'slatedb'
//!
//! db = SlateDb::Database.open("/tmp/mydb")
//! db.put("hello", "world")
//! db.get("hello") # => "world"
//! db.close
//! ```

use magnus::{define_module, Error, Ruby};

mod database;
mod errors;
mod iterator;
mod runtime;

/// Initialize the SlateDb Ruby module.
///
/// This is called automatically when the native extension is loaded.
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("SlateDb")?;

    // Define exception classes first
    errors::define_exceptions(ruby, &module)?;

    // Define core classes
    database::define_database_class(ruby, &module)?;
    iterator::define_iterator_class(ruby, &module)?;

    Ok(())
}
