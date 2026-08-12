# fastwarc-grpc

Streaming gRPC server exposing the `fastwarc` WARC parser. Binary gRPC only
(no JSON transcoding); the protobuf contracts live in [`proto/`](proto) and
follow the buf Standard (`STANDARD` + `COMMENTS` lint categories). See
[DESIGN.md](DESIGN.md) for the architecture and the lossless data mapping.

This is a standalone companion project to
[chatnoir-resiliparse](https://github.com/chatnoir-eu/chatnoir-resiliparse).
The library itself is untouched and carries no gRPC dependencies. The server
sits directly on the `fastwarc` Rust crate; there is no Python or Cython in
the serving path.

## Service

- `fastwarc.v1.WarcService/ParseWarc` (bidirectional streaming): send one
  `config` message, then raw archive bytes (`chunk`): plain, gzip, zstd, or
  lz4 (auto-detected when `stream_detect` is enabled, the default). Receive
  per kept record: `record_start` (full metadata, lossless header blocks),
  `payload_chunk`* (offset-tagged), `record_end` (payload length, digest
  verification results). HTTP-header failures on a framed record yield a
  recoverable `record_error`; WARC framing failures end the stream
  (non-recoverable).
- `fastwarc.v1.WarcService/ParseArchive` (unary): the whole archive in one
  request, every kept record (metadata, whole payload, digest statuses) in
  one response — for single records and small archives within the gRPC
  message size limits (4 MiB by default). Same parse pipeline, filters, and
  error model as the stream; a framing error returns the records parsed so
  far plus one non-recoverable error.
- Filters matching Python `ArchiveIterator`: `record_types`,
  `min_content_length`, `max_content_length`, and `BuiltinFilter` predicates.
- `grpc.health.v1.Health` for load-balancer probes.
- gRPC server reflection (v1), so tools like `grpcurl` can discover and
  call the service without local copies of the proto files:

```sh
grpcurl -plaintext localhost:50051 describe fastwarc.v1.WarcService
grpcurl -plaintext \
  -d "{\"config\":{}, \"archive\":\"$(base64 -w0 record.warc)\"}" \
  localhost:50051 fastwarc.v1.WarcService/ParseArchive
```

### Python parity notes

| Local Python default | gRPC |
|---|---|
| `parse_http=True` | `parse_http` defaults **false** — set `true` for parity |
| `verify_digests` skips bad records | still emits; status on `record_end` |
| `func_filter=callable` | use `BuiltinFilter` or filter client-side |
| writing / fsspec / pickle | out of scope (local-only) |

## Build

Pure Rust: no native libraries, no vcpkg, no libclang.

```sh
cargo build
```

The server builds against the published
[`fastwarc`](https://crates.io/crates/fastwarc) crate; no checkout of
chatnoir-resiliparse and no fork-specific patches are required.

## Run

```sh
FASTWARC_GRPC_ADDR="[::]:50051" cargo run
```

The server shuts down gracefully on SIGINT or SIGTERM.

An example client streams a local archive and prints a per-record summary:

```sh
cargo run --example parse -- tests/data/warcfile.warc.gz
```

## Lint and test gates

CI (`.github/workflows/ci.yml`) runs exactly these:

```sh
cd proto && buf lint && buf format --diff --exit-code
cargo fmt --check
cargo clippy --all-targets --no-deps -- -D warnings -D clippy::pedantic
cargo test
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
```

The WARC fixtures under `tests/data/` are unmodified copies from the
chatnoir-resiliparse test corpus, so parity assertions run against the same
inputs the library itself is tested with. The one addition is
`warcfile.warc.zst`, a zstd re-compression of `warcfile.warc` covering the
zstd autodetection path (the upstream corpus has no plain zstd archive).
