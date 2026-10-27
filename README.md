# fastwarc-grpc

Container image for the streaming gRPC server that exposes the `fastwarc`
WARC parser. The server itself is the official
[`fastwarc-grpc`](https://crates.io/crates/fastwarc-grpc) crate, published
from [chatnoir-resiliparse](https://github.com/chatnoir-eu/chatnoir-resiliparse)
(`fastwarc-grpc/`). This repo pins a crate version, builds it into a hardened
image, smoke-tests the image, and publishes it as
`docker.io/pipestreamai/fastwarc-grpc`. There is no server source here: code
changes go upstream.

| What | Where |
|---|---|
| Pinned crate version | `ARG FASTWARC_GRPC_VERSION` in [`Dockerfile`](Dockerfile) (currently 1.1.0) |
| Contract | [`proto/fastwarc/v1/`](proto/fastwarc/v1), byte-identical to the pinned crate's `proto/` |
| Test archives | [`tests/data/`](tests/data), copies from the chatnoir-resiliparse test corpus plus a zstd re-compression of `warcfile.warc` |

## Service

- `fastwarc.v1.WarcService/ParseWarc` (bidirectional streaming): send one
  `config` message, then raw archive bytes (`chunk`): plain, gzip, zstd, or
  lz4 (auto-detected unless `stream_detect` is false). Receive per kept
  record: `record_start` (metadata and header blocks), `payload_chunk`*,
  `record_end` (payload length). `response_batch_size` packs several of those
  events into one `batch` message. HTTP-header failures yield a recoverable
  `record_error`; WARC framing failures end the stream.
- `fastwarc.v1.WarcService/ParseArchive` (unary): the whole archive in one
  request, records and errors in one response, for archives within the gRPC
  message limit (the decoded response is budgeted at 16 MiB).
- `grpc.health.v1.Health` and gRPC server reflection (v1).

```sh
grpcurl -plaintext localhost:50060 describe fastwarc.v1.WarcService
grpcurl -plaintext \
  -d "{\"config\":{}, \"archive\":\"$(base64 -w0 tests/data/warcfile.warc.gz)\"}" \
  localhost:50060 fastwarc.v1.WarcService/ParseArchive
```

Defaults that differ from a reader's expectations: `parse_http` is true when
unset, and `verify_digests` skips records with a missing or invalid
`WARC-Block-Digest` (the same as the Python and Rust iterators).

## Configuration

| Variable | Default in this image | Meaning |
|---|---|---|
| `FASTWARC_GRPC_ADDR` | `0.0.0.0:50060` | Listen address (`unix:/path` for a socket). The crate's own default is `[::]:50061`; the image keeps the fleet's 50060 |
| `FASTWARC_GRPC_MAX_CONCURRENT_PARSERS` | crate default | Cap on parses running at once |
| `FASTWARC_GRPC_ALLOW_LOCAL_FILES` | unset (off) | Lets `ParseWarc` read `archive_path` on the server; leave off in a container |
| `FASTWARC_GRPC_LOCAL_FILE_ROOT` | unset | The jail `archive_path` resolves inside when local files are on |

## Docker

```bash
docker build -t fastwarc-grpc .
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges \
  -p 50060:50060 fastwarc-grpc
```

The build stage is `dhi.io/rust:1-dev` with `protobuf-compiler` from apt
(the crate's `build.rs` compiles its protos) and runs
`cargo install --locked fastwarc-grpc --version =<pin>`, so the image uses
the dependency lockfile the crate was published with. The runtime is
`dhi.io/debian-base:trixie-debian13`: no package manager, no shell, non-root,
which is why health checking is the orchestrator's job over
`grpc.health.v1.Health/Check` rather than a Dockerfile `HEALTHCHECK`.

The published image is multi-arch (`linux/amd64` + `linux/arm64`):

```bash
docker pull pipestreamai/fastwarc-grpc:latest
docker run --rm -p 50060:50060 pipestreamai/fastwarc-grpc:latest
```

## Bumping the crate

```sh
# 1. edit ARG FASTWARC_GRPC_VERSION in the Dockerfile
scripts/check-proto-pin.sh --sync   # 2. copy the new crate's protos into proto/
scripts/check-proto-pin.sh          # 3. confirm
```

Then rebuild, run `scripts/smoke.sh`, and re-vendor the protos into every
client that carries a copy.

## Lint and test gates

CI (`.github/workflows/ci.yml`) runs exactly these:

```sh
cd proto && buf lint && buf format --diff --exit-code
scripts/check-proto-pin.sh
docker build -t fastwarc-grpc:ci .
# run the image on :50060, then
scripts/smoke.sh localhost:50060
```
