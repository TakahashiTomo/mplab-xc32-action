#!/bin/bash
set -euo pipefail

PROJECT_RAW="${1:?project path is required}"
CONFIG="${2:?configuration is required}"
PACKS="${3:-}"

echo "=== XC32 Build Action ==="
echo "Project (raw): ${PROJECT_RAW}"
echo "Configuration : ${CONFIG}"
echo "Packs         : ${PACKS}"

# 1) プロジェクトパス解決
WS="/github/workspace"
CANDS=("${PROJECT_RAW}" "${WS}/${PROJECT_RAW}")
IFS='/' read -r _first rest <<< "${PROJECT_RAW}"
if [[ -n "${rest:-}" ]]; then CANDS+=("${rest}" "${WS}/${rest}"); fi

PROJECT_DIR=""
for p in "${CANDS[@]}"; do
  if [[ -d "$p" ]]; then PROJECT_DIR="$p"; break; fi
done
if [[ -z "${PROJECT_DIR}" ]]; then
  echo "Error: project dir not found. candidates:"; printf ' - %s\n' "${CANDS[@]}"; exit 1
fi
echo "Resolved project dir: ${PROJECT_DIR}"

NB_MK="${PROJECT_DIR}/nbproject/Makefile-${CONFIG}.mk"
NB_VAR="${PROJECT_DIR}/nbproject/Makefile-variables.mk"
ROOT_MK="${PROJECT_DIR}/Makefile"

# 2) 必須ファイル確認
for f in "${NB_MK}" "${NB_VAR}" "${ROOT_MK}"; do
  [[ -f "$f" ]] || { echo "Error: missing $f"; exit 2; }
done

# 3) 改行を LF に統一（CRLF 由来の不具合防止）
sed -i 's/\r$//' "${NB_MK}"
sed -i 's/\r$//' "${NB_VAR}"
sed -i 's/\r$//' "${ROOT_MK}"

# 4) Windows → Linux サニタイズ
#   - SHELL=cmd.exe → /bin/sh
#   - Windows の XC32 実行ファイルパス → Linux の /opt/microchip/xc32/v4.45/bin
#   - Java/DEP_GEN 等の IDE 依存は無効化
#   - PATH 行は XC32/bin を先頭に
XC32_BIN="/opt/microchip/xc32/v4.45/bin"

# SHELL
if grep -q '^SHELL=cmd.exe' "${NB_MK}"; then
  sed -i 's|^SHELL=.*|SHELL=/bin/sh|' "${NB_MK}"
fi

# PATH_TO_IDE_BIN / MP_JAVA_PATH / DEP_GEN をコメントアウト
sed -i -e 's|^PATH_TO_IDE_BIN=.*|# PATH_TO_IDE_BIN (disabled in CI)|' \
       -e 's|^MP_JAVA_PATH=.*|# MP_JAVA_PATH (disabled in CI)|' \
       -e 's|^DEP_GEN=.*|DEP_GEN=echo "Skipping dependency generation"|' "${NB_MK}"

# XC32 実行ファイル (Windows → Linux)
# 例: "C:\Program Files\Microchip\xc32\v4.45\bin\xc32-gcc.exe"
sed -i \
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
  "${NB_MK}"

# PATH 先頭を XC32/bin に
if grep -q '^PATH:=' "${NB_MK}"; then
  sed -i "s|^PATH:=.*|PATH:=${XC32_BIN}:\$(PATH)|" "${NB_MK}"
else
  echo "PATH:=${XC32_BIN}:\$(PATH)" >> "${NB_MK}"
fi

# Windows 絶対パスの CMSIS/DFP はコメントアウト（packs か相対で解決）
sed -i -e 's|^CMSIS_DIR=.*|# CMSIS_DIR (set by project/packs)|' \
       -e 's|^DFP_DIR=.*|# DFP_DIR (set by project/packs)|' "${NB_MK}"

# 5) 何が書き換わったかを先頭 80 行で確認
echo "=== DEBUG: head of ${NB_MK} ==="
sed -n '1,80p' "${NB_MK}"

# 6) XC32 を PATH に載せる / packs を環境へ
export PATH="${XC32_BIN}:${PATH}"
export DFP_PACKS="${PACKS}"

# 7) ビルド（ルート Makefile を直接呼ぶ -> 再帰ループなし）
echo "=== Building with make (root Makefile) ==="
# デバッグを濃くしたい場合は --trace を有効化
MAKEFLAGS=${MAKEFLAGS:-}
make --no-builtin-rules --trace -C "${PROJECT_DIR}" CONF="${CONFIG}" build

echo "=== Build Completed Successfully ==="
