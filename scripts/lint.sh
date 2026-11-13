#!/usr/bin/env bash
# Vérifie le format Swift avec swift-format (lecture seule, ne modifie rien).
# Usage : scripts/lint.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

swift format lint --strict --configuration .swift-format -r HermesKit/Sources HermesKit/Tests
