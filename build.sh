#!/bin/bash
set -euo pipefail

PROJECT="$1"
CONFIG="$2"
PACKS="${3:-}"

echo "=== XC32 Build Action ==="
echo "Project: ${PROJECT}"
echo "Configuration: ${CONFIG}"
echo "Packs: ${PACKS}"

export DFP_PACKS="${PACKS}"

if [ ! -d "$PROJECT" ]; then
    echo "Error: Project directory not found: $PROJECT"
    exit 1
fi

echo "=== Building with make ==="
make -C "$PROJECT" CONF="$CONFIG" build

echo "=== Build Completed Successfully ==="
