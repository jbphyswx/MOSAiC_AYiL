#!/usr/bin/env bash
echo "chunk_warmstart_smoke_test.sh moved to scripts/manual/ (not part of ./test/run_tests.sh)" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manual/chunk_warmstart_smoke_test.sh" "$@"
