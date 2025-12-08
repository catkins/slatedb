use std::sync::Arc;

use magnus::prelude::*;
use magnus::{function, method, Error, RHash, Ruby, TryConvert};
use slatedb::admin::AdminBuilder;
use slatedb::config::{CheckpointOptions, GarbageCollectorOptions};

use crate::errors::{invalid_argument_error, map_error};
use crate::runtime::block_on;

/// Helper to extract an optional value from an RHash
fn get_optional<T: TryConvert>(hash: &RHash, key: &str) -> Result<Option<T>, Error> {
    let ruby = Ruby::get().expect("Ruby runtime not available");
    let sym = ruby.to_symbol(key);
    match hash.get(sym) {
        Some(val) => {
            if val.is_nil() {
                Ok(None)
            } else {
                Ok(Some(T::try_convert(val)?))
            }
        }
        None => Ok(None),
    }
}

/// Ruby wrapper for SlateDB Admin.
///
/// This struct is exposed to Ruby as `SlateDb::Admin`.
/// Provides administrative functions for managing manifests, checkpoints, and GC.
#[magnus::wrap(class = "SlateDb::Admin", free_immediately, size)]
pub struct Admin {
    inner: slatedb::admin::Admin,
}

impl Admin {
    /// Create an admin handle for a database path/object store.
    ///
    /// # Arguments
    /// * `path` - The path identifier for the database
    /// * `url` - Optional object store URL
    pub fn new(path: String, url: Option<String>) -> Result<Self, Error> {
        

        let admin = block_on(async {
            let object_store: Arc<dyn object_store::ObjectStore> = if let Some(ref url) = url {
                slatedb::Db::resolve_object_store(url).map_err(map_error)?
            } else {
                Arc::new(object_store::memory::InMemory::new())
            };

            Ok::<_, Error>(AdminBuilder::new(path, object_store).build())
        })?;

        Ok(Self { inner: admin })
    }

    /// Read the latest or a specific manifest as a JSON string.
    ///
    /// # Arguments
    /// * `id` - Optional manifest id to read. If None, reads the latest.
    ///
    /// # Returns
    /// JSON string of the manifest, or None if no manifests exist.
    pub fn read_manifest(&self, id: Option<u64>) -> Result<Option<String>, Error> {
        

        block_on(async { self.inner.read_manifest(id).await })
            .map_err(|e| {
                let ruby = Ruby::get().expect("Ruby runtime not available");
                Error::new(ruby.exception_runtime_error(), format!("{}", e))
            })
    }

    /// List manifests within an optional [start, end) range as JSON.
    ///
    /// # Arguments
    /// * `start` - Optional inclusive start id
    /// * `end_id` - Optional exclusive end id
    ///
    /// # Returns
    /// JSON string containing a list of manifest metadata.
    pub fn list_manifests(&self, start: Option<u64>, end_id: Option<u64>) -> Result<String, Error> {
        

        let range = match (start, end_id) {
            (Some(s), Some(e)) => s..e,
            (Some(s), None) => s..u64::MAX,
            (None, Some(e)) => 0..e,
            (None, None) => 0..u64::MAX,
        };

        block_on(async { self.inner.list_manifests(range).await })
            .map_err(|e| {
                let ruby = Ruby::get().expect("Ruby runtime not available");
                Error::new(ruby.exception_runtime_error(), format!("{}", e))
            })
    }

    /// Create a detached checkpoint.
    ///
    /// # Arguments
    /// * `kwargs` - Options: lifetime (ms), source (UUID string), name
    ///
    /// # Returns
    /// Hash with id (UUID string) and manifest_id (int)
    pub fn create_checkpoint(&self, kwargs: RHash) -> Result<RHash, Error> {
        let lifetime =
            get_optional::<u64>(&kwargs, "lifetime")?.map(std::time::Duration::from_millis);
        let source = get_optional::<String>(&kwargs, "source")?;
        let name = get_optional::<String>(&kwargs, "name")?;

        // Parse source UUID if provided
        let source_uuid = if let Some(ref s) = source {
            Some(
                uuid::Uuid::parse_str(s)
                    .map_err(|e| invalid_argument_error(&format!("invalid source UUID: {}", e)))?,
            )
        } else {
            None
        };

        let options = CheckpointOptions {
            lifetime,
            source: source_uuid,
            name,
        };

        
        let result = block_on(async { self.inner.create_detached_checkpoint(&options).await })
            .map_err(map_error)?;

        let ruby = Ruby::get().expect("Ruby runtime not available");
        let hash = ruby.hash_new();
        hash.aset(ruby.to_symbol("id"), result.id.to_string())?;
        hash.aset(ruby.to_symbol("manifest_id"), result.manifest_id)?;

        Ok(hash)
    }

    /// List known checkpoints for the database.
    ///
    /// # Arguments
    /// * `name` - Optional checkpoint name filter
    ///
    /// # Returns
    /// Array of checkpoint hashes
    pub fn list_checkpoints(&self, name: Option<String>) -> Result<magnus::RArray, Error> {
        

        let checkpoints = block_on(async { self.inner.list_checkpoints(name.as_deref()).await })
            .map_err(|e| {
                let ruby = Ruby::get().expect("Ruby runtime not available");
                Error::new(ruby.exception_runtime_error(), format!("{}", e))
            })?;

        let ruby = Ruby::get().expect("Ruby runtime not available");
        let result = ruby.ary_new_capa(checkpoints.len());

        for cp in checkpoints {
            let hash = ruby.hash_new();
            hash.aset(ruby.to_symbol("id"), cp.id.to_string())?;
            hash.aset(ruby.to_symbol("manifest_id"), cp.manifest_id)?;
            hash.aset(
                ruby.to_symbol("expire_time"),
                cp.expire_time.map(|t| t.to_rfc3339()),
            )?;
            hash.aset(ruby.to_symbol("create_time"), cp.create_time.to_rfc3339())?;
            hash.aset(ruby.to_symbol("name"), cp.name)?;
            result.push(hash)?;
        }

        Ok(result)
    }

    /// Refresh a checkpoint's lifetime.
    ///
    /// # Arguments
    /// * `id` - Checkpoint UUID string
    /// * `lifetime` - Optional new lifetime in milliseconds
    pub fn refresh_checkpoint(&self, id: String, lifetime: Option<u64>) -> Result<(), Error> {
        let checkpoint_uuid = uuid::Uuid::parse_str(&id)
            .map_err(|e| invalid_argument_error(&format!("invalid checkpoint UUID: {}", e)))?;

        let lifetime_duration = lifetime.map(std::time::Duration::from_millis);

        
        block_on(async {
            self.inner
                .refresh_checkpoint(checkpoint_uuid, lifetime_duration)
                .await
        })
        .map_err(map_error)?;

        Ok(())
    }

    /// Delete a checkpoint.
    ///
    /// # Arguments
    /// * `id` - Checkpoint UUID string
    pub fn delete_checkpoint(&self, id: String) -> Result<(), Error> {
        let checkpoint_uuid = uuid::Uuid::parse_str(&id)
            .map_err(|e| invalid_argument_error(&format!("invalid checkpoint UUID: {}", e)))?;

        
        block_on(async { self.inner.delete_checkpoint(checkpoint_uuid).await })
            .map_err(map_error)?;

        Ok(())
    }

    /// Run garbage collection once.
    ///
    /// # Arguments
    /// * `_kwargs` - GC options (currently unused, uses defaults)
    pub fn run_gc(&self, _kwargs: RHash) -> Result<(), Error> {
        // Use default GC options - the structure is complex with nested directory options
        let gc_opts = GarbageCollectorOptions::default();

        
        block_on(async { self.inner.run_gc_once(gc_opts).await })
            .map_err(|e| {
                let ruby = Ruby::get().expect("Ruby runtime not available");
                Error::new(ruby.exception_runtime_error(), format!("{}", e))
            })?;

        Ok(())
    }
}

/// Define the Admin class on the SlateDb module.
pub fn define_admin_class(ruby: &Ruby, module: &magnus::RModule) -> Result<(), Error> {
    let class = module.define_class("Admin", ruby.class_object())?;

    // Class methods
    class.define_singleton_method("_new", function!(Admin::new, 2))?;

    // Instance methods
    class.define_method("_read_manifest", method!(Admin::read_manifest, 1))?;
    class.define_method("_list_manifests", method!(Admin::list_manifests, 2))?;
    class.define_method("_create_checkpoint", method!(Admin::create_checkpoint, 1))?;
    class.define_method("_list_checkpoints", method!(Admin::list_checkpoints, 1))?;
    class.define_method("_refresh_checkpoint", method!(Admin::refresh_checkpoint, 2))?;
    class.define_method("_delete_checkpoint", method!(Admin::delete_checkpoint, 1))?;
    class.define_method("_run_gc", method!(Admin::run_gc, 1))?;

    Ok(())
}
