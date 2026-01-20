
#!/bin/bash
set -euo pipefail

PROJECT="$1"
CONFIG="$2"
PACKS="${3:-}"

echo "=== XC32 Build Action ==="
echo "Project: ${PROJECT}"
echo "Configuration: ${CONFIG}"
echo "Packs: ${PACKS}"

# DFP packs を環境変数として渡す（必要なら使う）
export DFP_PACKS="${PACKS}"

# Makefile が存在するか確認
if [ ! -d "$PROJECT" ]; then
    echo "Error: Project directory not found: $PROJECT"
    exit 1
fi

if [ ! -f "$PROJECT/Makefile" ] && [ ! -f "$PROJECT/nbproject/Makefile-${CONFIG}.mk" ]; then
    echo "Error: No Makefile found inside project $PROJECT"
    exit 2
fi

echo "=== Building with make ==="
make -C "$PROJECT" CONF="$CONFIG" build

echo "=== Build Completed Successfully ==="
