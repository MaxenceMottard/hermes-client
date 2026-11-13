#!/usr/bin/env bash
# Lance les tests du package HermesKit.
# Usage : scripts/test.sh [arguments supplémentaires pour `swift test`]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/HermesKit"

swift test "$@"
