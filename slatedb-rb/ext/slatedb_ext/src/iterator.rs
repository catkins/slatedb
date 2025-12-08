use magnus::prelude::*;
use magnus::Error;

/// Placeholder for Iterator - will be implemented in Milestone 2.
/// For now, we just need this module to exist so database.rs compiles.
#[magnus::wrap(class = "SlateDb::Iterator", free_immediately, size)]
pub struct Iterator {
    // Will hold DbIterator in Milestone 2
    _placeholder: (),
}

impl Iterator {
    #[allow(dead_code)]
    pub fn new() -> Self {
        Self { _placeholder: () }
    }
}

/// Define the Iterator class on the SlateDb module.
pub fn define_iterator_class(ruby: &magnus::Ruby, module: &magnus::RModule) -> Result<(), Error> {
    let _class = module.define_class("Iterator", ruby.class_object())?;
    // Methods will be added in Milestone 2
    Ok(())
}
