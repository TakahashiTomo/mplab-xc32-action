#!/bin/bash
set -euo pipefail

PROJECT_RAW="${1:?project path is required}"
CONFIG="${2:?configuration is required}"
PACKS="${3:-}"

echo "=== XC32 Build Action ==="
echo "Project (raw): ${PROJECT_RAW}"
echo "Configuration : ${CONFIG}"
echo "Packs         : ${PACKS}"

WS="/github/workspace"
CANDIDATES=("${PROJECT_RAW}" "${WS}/${PROJECT_RAW}")

IFS='/' read -r _first rest <<< "${PROJECT_RAW}"
if [[ -n "${rest:-}" ]]; then
  CANDIDATES+=("${rest}" "${WS}/${rest}")
fi

PROJECT_DIR=""
for p in "${CANDIDATES[@]}"; do
  if [[ -d "$p" ]]; then
    PROJECT_DIR="$p"
    break
  fi
done

if [[ -z "${PROJECT_DIR}" ]]; then
  echo "Error: Project directory not found."
  exit 1
fi

echo "Resolved project dir: ${PROJECT_DIR}"

# ------------------------------------------------------------------------------
# Copy Linux Makefile (never generate inline)
# ------------------------------------------------------------------------------
SRC_LINUX_MK="${PROJECT_DIR}/nbproject/Makefile-${CONFIG}-linux.mk"
DST_MK="${PROJECT_DIR}/nbproject/Makefile-${CONFIG}.mk"

if [[ ! -f "${SRC_LINUX_MK}" ]]; then
  echo "Error: Linux Makefile template not found: ${SRC_LINUX_MK}"
  exit 2
fi

cp "${SRC_LINUX_MK}" "${DST_MK}"
echo "[OK] Copied Linux Makefile to ${DST_MK}"

# ------------------------------------------------------------------------------
# Remove CRLF
# ------------------------------------------------------------------------------
sed -i 's/\r$//' "${DST_MK}"
sed -i 's/\r$//' "${PROJECT_DIR}/nbproject/Makefile-variables.mk"

# ------------------------------------------------------------------------------
# PATH / packs
# ------------------------------------------------------------------------------
XC32_BIN="/opt/microchip/xc32/v4.45/bin"
export PATH="${XC32_BIN}:${PATH}"
export DFP_PACKS="${PACKS}"

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------
if [[ ! -f "${PROJECT_DIR}/Makefile" ]]; then
  echo "Error: Root Makefile missing."
  exit 3
fi

echo "=== Building with make ==="
make -C "${PROJECT_DIR}" CONF="${CONFIG}" build

echo "=== Build Completed Successfully ==="
