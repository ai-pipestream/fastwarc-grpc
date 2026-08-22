# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# Build stage.
#
# The tests run here, against the release profile the image ships, before the
# binary is built, so a red suite fails the image rather than shipping. That
# is the whole reason this is a multi-stage build and not a `COPY` of
# something built on a laptop: the artifact and the evidence for it come out
# of the same command.
#
# protoc IS needed here (unlike grpc-lol-html/grpc-epub/grpc-pdf-inspector):
# build.rs drives tonic-prost-build over proto/ on every build, and this crate
# has no committed generated stubs (see src/lib.rs's `include_proto!`). So the
# dev variant of the hardened toolchain image is used: it carries apt (needed
# for protoc) and runs as root, where the plain dhi.io/rust:1 runtime-style
# image has no package manager at all.
# ---------------------------------------------------------------------------
FROM dhi.io/rust:1-dev AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      protobuf-compiler libprotobuf-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

# `--locked` makes the build reproducible and fails loudly if Cargo.lock is out
# of date, rather than quietly resolving to something never tested.
RUN cargo test --release --locked
RUN cargo build --release --locked --bin fastwarc-grpc \
    && strip target/release/fastwarc-grpc

# ---------------------------------------------------------------------------
# Runtime stage.
#
# Docker Hardened Images debian-base: glibc and libgcc, no package manager,
# pulls from the docker.io ecosystem (dhi.io) with signed provenance, and
# runs as uid 65532 out of the box. There is no hot path that needs a shell,
# and this service never writes to disk, so the container can and should run
# with `--read-only`.
#
#   docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges \
#     -p 50060:50060 fastwarc-grpc
#
# Health checking is the orchestrator's job over
# gRPC (`grpc.health.v1.Health/Check`, which this server registers) rather than
# a Dockerfile HEALTHCHECK, because there is no shell here to run one with.
# ---------------------------------------------------------------------------
FROM dhi.io/debian-base:trixie-debian13

COPY --from=builder /src/target/release/fastwarc-grpc /usr/local/bin/fastwarc-grpc

ENV FASTWARC_GRPC_ADDR=0.0.0.0:50060
EXPOSE 50060
USER nonroot
ENTRYPOINT ["/usr/local/bin/fastwarc-grpc"]
