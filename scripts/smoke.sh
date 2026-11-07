#!/usr/bin/env bash
# Smoke-tests a running fastwarc-grpc server: reflection lists
# fastwarc.v1.WarcService, and ParseArchive returns every record of each fixture under
# tests/data with no record errors. Needs grpcurl; the contract comes from
# proto/, so this also proves the vendored copy speaks to the server.
#
#   scripts/smoke.sh [host:port]          default localhost:50060
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-localhost:50060}"

services="$(grpcurl -plaintext -max-time 10 "$target" list)"
if ! grep -qx 'fastwarc.v1.WarcService' <<<"$services"; then
  echo "reflection does not list fastwarc.v1.WarcService: $services" >&2
  exit 1
fi

# Record counts from the upstream test corpus. The plain, gzip, lz4 and zstd
# forms of warcfile are one archive, so they must agree.
declare -A expected=(
  [warcfile.warc]=50
  [warcfile.warc.gz]=50
  [warcfile.warc.lz4]=50
  [warcfile.warc.zst]=50
)

status=0
for fixture in "${!expected[@]}"; do
  response="$(base64 -w0 "$root/tests/data/$fixture" |
    awk '{ printf "{\"config\":{\"include_payload\":false},\"archive\":\"%s\"}", $0 }' |
    grpcurl -plaintext -max-time 30 -max-msg-sz 67108864 \
      -import-path "$root/proto" -proto fastwarc/v1/warc_service.proto \
      -d @ "$target" fastwarc.v1.WarcService/ParseArchive)"
  records="$(grep -c '"recordType"' <<<"$response" || true)"
  errors="$(grep -c '"recoverable"\|"message"' <<<"$response" || true)"
  if [ "$records" -ne "${expected[$fixture]}" ] || [ "$errors" -ne 0 ]; then
    echo "$fixture: $records records (want ${expected[$fixture]}), $errors error fields" >&2
    status=1
  else
    echo "$fixture: $records records"
  fi
done
exit "$status"
