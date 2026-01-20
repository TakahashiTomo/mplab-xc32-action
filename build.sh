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
  if [[ -d "$p" ]]; then PROJECT_DIR="$p"; break; fi
done
if [[ -z "${PROJECT_DIR}" ]]; then
  echo "Error: Project directory not found in candidates:"
  printf '  - %s\n' "${CANDIDATES[@]}"; exit 1
fi
echo "Resolved project dir: ${PROJECT_DIR}"

# === ここから “Windows→Linux” 修正（SANITIZE） =====================
MAKE_MK="${PROJECT_DIR}/nbproject/Makefile-${CONFIG}.mk"
VAR_MK="${PROJECT_DIR}/nbproject/Makefile-variables.mk"

if [[ ! -f "${MAKE_MK}" ]]; then
  echo "Error: ${MAKE_MK} not found."; exit 2
fi
if [[ ! -f "${VAR_MK}" ]]; then
  echo "Error: ${VAR_MK} not found."; exit 2
fi

# CRLF を除去
sed -i 's/\r$//' "${MAKE_MK}"
sed -i 's/\r$//' "${VAR_MK}"

# Windows 固有のシェル/パス/ツール設定を Linux 用に置換
# - SHELL=cmd.exe → /bin/sh
# - PATH は XC32 の bin を先頭に
# - MP_* ツールのフル Windows パス → Linux の XC32 インストール先
# - IDE/JAVA 依存の行はコメントアウト
XC32_BIN="/opt/microchip/xc32/v4.45/bin"

sed -i \
  -e 's|^SHELL=.*|SHELL=/bin/sh|' \
  -e "s|^PATH_TO_IDE_BIN=.*|# PATH_TO_IDE_BIN unused on CI|" \
  -e "s|^PATH:=.*|PATH:=${XC32_BIN}:\$(PATH)|" \
  -e 's|^MP_JAVA_PATH=.*|# MP_JAVA_PATH=|' \
  -e "s|^MP_CC=.*|MP_CC=${XC32_BIN}/xc32-gcc|" \
  -e "s|^MP_CPPC=.*|MP_CPPC=${XC32_BIN}/xc32-g++|" \
  -e "s|^MP_AS=.*|MP_AS=${XC32_BIN}/xc32-as|" \
  -e "s|^MP_LD=.*|MP_LD=${XC32_BIN}/xc32-ld|" \
  -e "s|^MP_AR=.*|MP_AR=${XC32_BIN}/xc32-ar|" \
  -e "s|^MP_CC_DIR=.*|MP_CC_DIR=${XC32_BIN}|" \
  -e "s|^MP_CPPC_DIR=.*|MP_CPPC_DIR=${XC32_BIN}|" \
  -e "s|^MP_AS_DIR=.*|MP_AS_DIR=${XC32_BIN}|" \
  -e "s|^MP_LD_DIR=.*|MP_LD_DIR=${XC32_BIN}|" \
  -e "s|^MP_AR_DIR=.*|MP_AR_DIR=${XC32_BIN}|" \
  -e 's|^DEP_GEN=.*|# DEP_GEN unused on CI|' \
  "${MAKE_MK}"

# もし Windows の CMSIS/DFP 絶対パスが混ざっていたら無効化（必要に応じて設定）
sed -i \
  -e 's|^CMSIS_DIR=.*|# CMSIS_DIR (set by packs or project includes)|' \
  -e 's|^DFP_DIR=.*|# DFP_DIR (set by packs or project includes)|' \
  "${MAKE_MK}"

# なお、XC32 は Dockerfile で /opt/microchip/xc32/v4.45 に導入済み。
export PATH="${XC32_BIN}:${PATH}"
export DFP_PACKS="${PACKS}"
# === “Windows→Linux” 修正 ここまで ================================

# Makefile が揃っているか最終確認（念のため）
if [[ ! -f "${PROJECT_DIR}/Makefile" && ! -f "${PROJECT_DIR}/nbproject/Makefile-${CONFIG}.mk" ]]; then
  echo "Error: Makefile not found under ${PROJECT_DIR} (CONF=${CONFIG})"; exit 3
fi

echo "=== Building with make ==="
make -C "${PROJECT_DIR}" CONF="${CONFIG}" build

echo "=== Build Completed Successfully ==="
