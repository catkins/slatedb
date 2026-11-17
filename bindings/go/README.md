# SlateDB Go Binding

Official Go binding for SlateDB.

## Install

```bash
go get slatedb.io/slatedb-go
```

## Runtime Requirements

This binding uses cgo and links against the `slatedb_uniffi` shared library. To
build and run code that imports it you need:

- Go 1.25 or newer
- `CGO_ENABLED=1`
- a working C toolchain
- the `slatedb_uniffi` shared library on your platform loader path

If you are working from this repository, that usually means building
`slatedb-uniffi` and pointing `LD_LIBRARY_PATH` or `DYLD_LIBRARY_PATH` at
`target/debug` or `target/release`. See [DEVELOPMENT.md](DEVELOPMENT.md) for
more details.

Writable databases and readers enter a dedicated multi-threaded Tokio runtime
while opening so SlateDB's long-lived background tasks capture a multi-threaded
Tokio handle. Foreground binding calls are still made through the normal Go API.
By default, the runtime uses the host's available parallelism. Set
`SLATEDB_UNIFFI_RUNTIME_THREADS` to a positive integer before the first
`DbBuilder.Build()` or `DbReaderBuilder.Build()` call to override the worker
thread count for the lifetime of the process.

### Prebuilt shared libraries

Releases published with the UniFFI release workflow include shared libraries for Linux (glibc),
macOS, and Windows on x86-64 and ARM64. Download the library version that matches your Go module
version from [GitHub releases](https://github.com/slatedb/slatedb/releases).
`go get` does not download or install these libraries.

For Linux x86-64, use the following commands. Replace `X.Y.Z` with your Go module version.
Use `aarch64-unknown-linux-gnu` for Linux ARM64.

```bash
VERSION=X.Y.Z
TARGET=x86_64-unknown-linux-gnu
ARCHIVE="slatedb-uniffi-v${VERSION}-${TARGET}.tar.gz"

gh release download "v${VERSION}" --repo slatedb/slatedb \
  --pattern "$ARCHIVE" --pattern SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS
mkdir -p slatedb-native
tar -xzf "$ARCHIVE" -C slatedb-native

export CGO_LDFLAGS="-L$(pwd)/slatedb-native ${CGO_LDFLAGS:-}"
export LD_LIBRARY_PATH="$(pwd)/slatedb-native:${LD_LIBRARY_PATH:-}"
```

These variables let the C linker and runtime loader find the library when you build and run Go code.
Linux archives require a glibc-based system compatible with Ubuntu 22.04; they do not support Alpine
Linux. On macOS, use the matching `apple-darwin` archive and set `DYLD_LIBRARY_PATH` instead.
On Windows, extract the matching `pc-windows-msvc` archive and add its directory to `PATH`.

## Quick Start

```go
package main

import (
	"bytes"
	"fmt"

	slatedb "slatedb.io/slatedb-go/uniffi"
)

func main() {
	store, err := slatedb.ObjectStoreResolve("memory:///")
	if err != nil {
		panic(err)
	}
	defer store.Destroy()

	builder := slatedb.NewDbBuilder("example-db", store)
	defer builder.Destroy()

	db, err := builder.Build()
	if err != nil {
		panic(err)
	}
	defer db.Destroy()

	if _, err := db.Put([]byte("hello"), []byte("world")); err != nil {
		panic(err)
	}

	value, err := db.Get([]byte("hello"))
	if err != nil {
		panic(err)
	}
	if value == nil || !bytes.Equal(*value, []byte("world")) {
		panic("unexpected value")
	}

	fmt.Println(string(*value))

	if err := db.Shutdown(); err != nil {
		panic(err)
	}
}
```

## API Model

- `ObjectStoreResolve(...)` opens an object store from a URL such as
  `memory:///`
- `DbBuilder` opens a writable database and `DbReaderBuilder` opens a read-only
  reader
- `Db`, `DbReader`, and `DbSnapshot` support point reads, range scans, and
  prefix scans
- `Db.Begin(...)` opens a transaction at a chosen isolation level
- handle types own Rust-side resources, so call `Shutdown()` on databases and
  readers and `Destroy()` on handles when you are done with them

## Metrics

The Go binding exposes both custom metrics callbacks and the built-in
`DefaultMetricsRecorder`:

- `DbBuilder.WithMetricsRecorder(...)`
- `DbReaderBuilder.WithMetricsRecorder(...)`
- `NewDefaultMetricsRecorder()`
- `MetricByNameAndLabels(...)`

## Development

Maintainer workflows for regenerating bindings, running Go tests, and other
repository-specific tasks live in [DEVELOPMENT.md](DEVELOPMENT.md).
