#!/usr/bin/env bash
# Checks that proto/fastwarc/v1/ is byte-identical to the contract shipped in
# the fastwarc-grpc crate the Dockerfile pins. The version is read from the
# Dockerfile's FASTWARC_GRPC_VERSION argument, so bumping the pin without
# re-vendoring the protos (or the reverse) fails here.
#
#   scripts/check-proto-pin.sh            compare, exit 1 on any drift
#   scripts/check-proto-pin.sh --sync     copy the crate's protos into proto/
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mode=check
case "${1:-}" in
  "") ;;
  --sync) mode=sync ;;
  *) echo "usage: $0 [--sync]" >&2; exit 2 ;;
esac

version="$(sed -n 's/^ARG FASTWARC_GRPC_VERSION=//p' "$root/Dockerfile")"
if [ -z "$version" ]; then
  echo "no FASTWARC_GRPC_VERSION argument in the Dockerfile" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
# crates.io asks API clients to identify themselves.
curl -sSfL -A "fastwarc-grpc-image (https://github.com/ai-pipestream/fastwarc-grpc)" \
  -o "$work/crate.tar.gz" \
  "https://crates.io/api/v1/crates/fastwarc-grpc/${version}/download"
tar -xzf "$work/crate.tar.gz" -C "$work"
crate_protos="$work/fastwarc-grpc-${version}/proto/fastwarc/v1"

status=0
for file in warc.proto warc_service.proto; do
  if [ "$mode" = sync ]; then
    cp -- "$crate_protos/$file" "$root/proto/fastwarc/v1/$file"
  elif ! cmp -s -- "$crate_protos/$file" "$root/proto/fastwarc/v1/$file"; then
    echo "proto/fastwarc/v1/$file differs from fastwarc-grpc $version" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "proto/fastwarc/v1 matches fastwarc-grpc $version"
exit "$status"
