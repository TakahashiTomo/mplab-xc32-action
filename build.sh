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
# Generate Linux Makefile (TAB preserved)
# ------------------------------------------------------------------------------
LINUX_MK="${PROJECT_DIR}/nbproject/Makefile-${CONFIG}.mk"
VAR_MK="${PROJECT_DIR}/nbproject/Makefile-variables.mk"

if [[ ! -f "${VAR_MK}" ]]; then
  echo "Error: ${VAR_MK} not found"
  exit 2
fi

cat > "${LINUX_MK}" << 'EOF'
# Linux sanitized Makefile (CI auto‑generated)
SHELL=/bin/sh

XC32_DIR=/opt/microchip/xc32/v4.45
MP_CC=$(XC32_DIR)/bin/xc32-gcc
MP_CPPC=$(XC32_DIR)/bin/xc32-g++
MP_AS=$(XC32_DIR)/bin/xc32-as
MP_LD=$(XC32_DIR)/bin/xc32-ld
MP_AR=$(XC32_DIR)/bin/xc32-ar

PATH:=$(XC32_DIR)/bin:$(PATH)
DEP_GEN=echo "Skipping dependency generation"

CMSIS_DIR=
DFP_DIR=

include nbproject/Makefile-variables.mk

.build-conf:
    $(MAKE) -f Makefile CONF=$(CONF) build

.build-impl:
    $(MAKE) -f Makefile CONF=$(CONF) build
EOF

echo "[OK] Linux Makefile generated: ${LINUX_MK}"

# ------------------------------------------------------------------------------
# CRLF remove
# ------------------------------------------------------------------------------
sed -i 's/\r$//' "${LINUX_MK}"
sed -i 's/\r$//' "${VAR_MK}"

XC32_BIN="/opt/microchip/xc32/v4.45/bin"
export PATH="${XC32_BIN}:${PATH}"
export DFP_PACKS="${PACKS}"

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------
if [[ ! -f "${PROJECT_DIR}/Makefile" ]]; then
  echo "Error: Root Makefile not found."
  exit 3
fi

echo "=== Building with make ==="
make -C "${PROJECT_DIR}" CONF="${CONFIG}" build

echo "=== Build Completed Successfully ==="
