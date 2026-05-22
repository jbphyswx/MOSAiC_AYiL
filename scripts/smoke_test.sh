#!/usr/bin/env bash
echo "smoke_test.sh moved to scripts/manual/smoke_test.sh (not part of ./test/run_tests.sh)" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manual/smoke_test.sh" "$@"
