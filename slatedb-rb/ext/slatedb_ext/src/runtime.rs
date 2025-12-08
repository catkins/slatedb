
use once_cell::sync::OnceCell;
use tokio::runtime::Runtime;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();

/// Get or initialize the shared Tokio runtime for all SlateDB operations.
///
/// Unlike the Go bindings which create a runtime per database, we use a shared
/// runtime for simplicity. This matches the Python bindings approach.
pub fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Runtime::new().expect("Failed to create Tokio runtime")
    })
}
