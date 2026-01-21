#!/bin/bash
set -euo pipefail

# =============================================================================
# build.sh - Linux CI 用 最終版（Windows 汚染サニタイズ + flags 自動生成 + gnumkdir対策）
# =============================================================================

PROJECT_RAW="${1:?project path is required}"
CONFIG="${2:?configuration is required}"
PACKS="${3:-}"

echo "=== XC32 Build Action ==="
echo "Project (raw): ${PROJECT_RAW}"
echo "Configuration : ${CONFIG}"
echo "Packs         : ${PACKS}"

# -----------------------------------------------------------------------------
# 1) プロジェクトパス解決
# -----------------------------------------------------------------------------
WS="/github/workspace"
CANDS=("${PROJECT_RAW}" "${WS}/${PROJECT_RAW}")
IFS='/' read -r _first rest <<< "${PROJECT_RAW}"
if [[ -n "${rest:-}" ]]; then
  CANDS+=("${rest}" "${WS}/${rest}")
fi

PROJECT_DIR=""
for p in "${CANDS[@]}"; do
  if [[ -d "$p" ]]; then PROJECT_DIR="$p"; break; fi
done
if [[ -z "${PROJECT_DIR}" ]]; then
  echo "Error: project dir not found."; printf '  - %s\n' "${CANDS[@]}"; exit 1
fi
echo "Resolved project dir: ${PROJECT_DIR}"

NB_DIR="${PROJECT_DIR}/nbproject"
ROOT_MK="${PROJECT_DIR}/Makefile"
NB_MK_CFG="${NB_DIR}/Makefile-${CONFIG}.mk"

[[ -d "${NB_DIR}"      ]] || { echo "Error: nbproject missing"; exit 2; }
[[ -f "${ROOT_MK}"     ]] || { echo "Error: root Makefile missing"; exit 2; }
[[ -f "${NB_MK_CFG}"   ]] || { echo "Error: ${NB_MK_CFG} missing"; exit 2; }

# -----------------------------------------------------------------------------
# 2) 改行を LF に統一（CRLF 由来の不具合防止）
# -----------------------------------------------------------------------------
find "${NB_DIR}" -maxdepth 1 -name '*.mk' -print0 | xargs -0 -I{} sed -i 's/\r$//' "{}"
sed -i 's/\r$//' "${ROOT_MK}"

# -----------------------------------------------------------------------------
# 3) Windows → Linux サニタイズ（nbproject/*.mk を横断）
# -----------------------------------------------------------------------------
XC32_BIN="/opt/microchip/xc32/v4.45/bin"

echo "=== DEBUG(before): scan for cmd.exe / COMSPEC ==="
grep -n -E 'cmd\.exe|COMSPEC|ComSpec|MP_SHELL' -H "${NB_DIR}"/*.mk || true

for f in "${NB_DIR}"/*.mk; do
  # シェルと Windows 互換変数の無効化
  sed -i 's/^SHELL=.*/SHELL=\/bin\/sh/' "$f"
  sed -i 's/^COMSPEC=.*/# COMSPEC disabled in CI/' "$f" || true
  sed -i 's/^ComSpec=.*/# ComSpec disabled in CI/' "$f" || true
  sed -i 's/^MP_SHELL=.*/# MP_SHELL disabled in CI/' "$f" || true

  # PATH は XC32/bin 先頭へ
  if grep -q '^PATH:=' "$f"; then
    sed -i "s|^PATH:=.*|PATH:=${XC32_BIN}:\$(PATH)|" "$f"
  else
    printf 'PATH:=%s:$(PATH)\n' "${XC32_BIN}" >> "$f"
  fi

  # XC32 実行ファイル（Windows → Linux）
  sed -i "s|^MP_CC=.*|MP_CC=${XC32_BIN}/xc32-gcc|"     "$f"
  sed -i "s|^MP_CPPC=.*|MP_CPPC=${XC32_BIN}/xc32-g++|" "$f"
  sed -i "s|^MP_AS=.*|MP_AS=${XC32_BIN}/xc32-as|"      "$f"
  sed -i "s|^MP_LD=.*|MP_LD=${XC32_BIN}/xc32-ld|"      "$f"
  sed -i "s|^MP_AR=.*|MP_AR=${XC32_BIN}/xc32-ar|"      "$f"

  sed -i "s|^MP_CC_DIR=.*|MP_CC_DIR=${XC32_BIN}|"      "$f"
  sed -i "s|^MP_CPPC_DIR=.*|MP_CPPC_DIR=${XC32_BIN}|"  "$f"
  sed -i "s|^MP_AS_DIR=.*|MP_AS_DIR=${XC32_BIN}|"      "$f"
  sed -i "s|^MP_LD_DIR=.*|MP_LD_DIR=${XC32_BIN}|"      "$f"
  sed -i "s|^MP_AR_DIR=.*|MP_AR_DIR=${XC32_BIN}|"      "$f"

  # IDE/JAVA 依存・Windows 絶対パスは無効化
  sed -i 's|^PATH_TO_IDE_BIN=.*|# PATH_TO_IDE_BIN disabled|' "$f"
  sed -i 's|^MP_JAVA_PATH=.*|# MP_JAVA_PATH disabled|'       "$f"
  sed -i 's|^DEP_GEN=.*|DEP_GEN=echo "Skipping dependency generation"|' "$f"
  sed -i 's|^CMSIS_DIR=.*|# CMSIS_DIR disabled|'             "$f"
  sed -i 's|^DFP_DIR=.*|# DFP_DIR disabled|'                 "$f"

  # 🔧 ファイル操作コマンドの統一（gnumkdir 等のラッパー排除）
  sed -i 's/^MKDIR=.*/MKDIR=mkdir/'   "$f"
  sed -i 's/^RM=.*/RM=rm -f/'         "$f"
  sed -i 's/^RMDIR=.*/RMDIR=rm -rf/'  "$f"
  sed -i 's/^CP=.*/CP=cp/'            "$f" || true
  sed -i 's/^MV=.*/MV=mv/'            "$f" || true
done

echo "=== DEBUG(after): scan for cmd.exe / COMSPEC ==="
grep -n -E 'cmd\.exe|COMSPEC|ComSpec|MP_SHELL' -H "${NB_DIR}"/*.mk || true

echo "=== DEBUG: head of ${NB_MK_CFG} ==="
sed -n '1,140p' "${NB_MK_CFG}"

# -----------------------------------------------------------------------------
# 4) MPLAB X の flags 依存ファイルを “ダミー自動生成”
# -----------------------------------------------------------------------------
echo "=== Generating missing MPLAB X flag files (.generated_files) ==="
FLAG_LIST="$(
  grep -RhoE '\.generated_files/flags/[A-Za-z0-9_./-]+' \
    "${NB_MK_CFG}" \
    "${NB_DIR}/Makefile-impl.mk" \
    "${NB_DIR}/Makefile-local-${CONFIG}.mk" 2>/dev/null \
  | sort -u
)"
if [[ -n "${FLAG_LIST}" ]]; then
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    abs="${PROJECT_DIR}/${rel}"
    mkdir -p "$(dirname "${abs}")"
    : > "${abs}"
    echo "  created: ${rel}"
  done <<< "${FLAG_LIST}"
else
  echo "  no flag dependencies found."
fi

# -----------------------------------------------------------------------------
# 5) PATH / 環境
# -----------------------------------------------------------------------------
export PATH="${XC32_BIN}:${PATH}"
export SHELL=/bin/sh
export DFP_PACKS="${PACKS}"

# -----------------------------------------------------------------------------
# 6) ビルド（root Makefile を使う／ファイル操作コマンドをコマンドラインでも強制）
# -----------------------------------------------------------------------------
echo "=== Building with make (root Makefile) ==="
make --no-builtin-rules --trace \
  -C "${PROJECT_DIR}" \
  CONF="${CONFIG}" \
  MKDIR=mkdir RM="rm -f" RMDIR="rm -rf" CP=cp MV=mv \
  build

echo "=== Build Completed Successfully ==="
