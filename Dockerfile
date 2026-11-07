# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# Build stage.
#
# The server is the official `fastwarc-grpc` crate from crates.io, published
# out of chatnoir-resiliparse. This repo only packages it: the version below
# is the whole pin, and `proto/` holds a byte-identical copy of the contract
# that ships inside that crate (scripts/check-proto-pin.sh keeps the two in
# step). `--locked` builds against the Cargo.lock the crate was published
# with, so the image resolves the same dependency tree upstream tested.
#
# protoc is needed: the crate's build.rs drives tonic-prost-build over its
# protos. So the dev variant of the hardened toolchain image is used, which
# carries apt and runs as root.
# ---------------------------------------------------------------------------
FROM dhi.io/rust:1-dev AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      protobuf-compiler libprotobuf-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG FASTWARC_GRPC_VERSION=1.1.0
RUN cargo install --locked --root /out fastwarc-grpc --version "=${FASTWARC_GRPC_VERSION}" \
    && strip /out/bin/fastwarc-grpc

# ---------------------------------------------------------------------------
# Runtime stage.
#
# Docker Hardened Images debian-base: glibc and libgcc, no package manager,
# runs as uid 65532 out of the box. The server never writes to disk (local
# file access stays off unless FASTWARC_GRPC_ALLOW_LOCAL_FILES is set), so
# the container can and should run with `--read-only`.
#
#   docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges \
#     -p 50060:50060 fastwarc-grpc
#
# Health checking is the orchestrator's job over gRPC
# (`grpc.health.v1.Health/Check`, which the server registers) rather than a
# Dockerfile HEALTHCHECK, because there is no shell here to run one with.
# ---------------------------------------------------------------------------
FROM dhi.io/debian-base:trixie-debian13

COPY --from=builder /out/bin/fastwarc-grpc /usr/local/bin/fastwarc-grpc

# The crate listens on 50061 by default; the fleet has always reached this
# service on 50060, so the image keeps that.
ENV FASTWARC_GRPC_ADDR=0.0.0.0:50060
EXPOSE 50060
USER nonroot
ENTRYPOINT ["/usr/local/bin/fastwarc-grpc"]
