#!/bin/bash
set -euo pipefail

# =============================================================================
# build.sh (Linux CI 用最終版)
#  - プロジェクトパス自動解決
#  - nbproject/*.mk を横断して Windows 由来の定義を徹底サニタイズ
#  - XC32 v4.45 (Linux) パスへ置換
#  - CRLF -> LF 強制
#  - デバッグ出力で「どの行が効いたか」を可視化
#  - ルート Makefile を使ってビルド（再帰ループ回避）
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
  echo "Error: project dir not found. candidates:"
  printf '  - %s\n' "${CANDS[@]}"
  exit 1
fi
echo "Resolved project dir: ${PROJECT_DIR}"

NB_DIR="${PROJECT_DIR}/nbproject"
NB_MK="${NB_DIR}/Makefile-${CONFIG}.mk"
NB_VAR="${NB_DIR}/Makefile-variables.mk"
ROOT_MK="${PROJECT_DIR}/Makefile"

# 必須ファイル確認
for f in "${NB_MK}" "${NB_VAR}" "${ROOT_MK}"; do
  [[ -f "$f" ]] || { echo "Error: missing $f"; exit 2; }
done

# -----------------------------------------------------------------------------
# 2) 改行を LF に統一（CRLF 由来の不具合防止）
# -----------------------------------------------------------------------------
find "${NB_DIR}" -maxdepth 1 -name '*.mk' -print0 | xargs -0 -I{} sed -i 's/\r$//' "{}"
sed -i 's/\r$//' "${ROOT_MK}"

# -----------------------------------------------------------------------------
# 3) サニタイズ（Windows → Linux）
#    - SHELL=cmd.exe / COMSPEC などを徹底除去
#    - XC32 実行ファイル/ディレクトリを Linux パスへ
#    - PATH は XC32/bin を先頭に
#    - IDE/JAVA 依存を無効化
#    - Windows 絶対パスの CMSIS/DFP はコメントアウト
# -----------------------------------------------------------------------------
pushd "${NB_DIR}" >/dev/null

XC32_BIN="/opt/microchip/xc32/v4.45/bin"

echo "=== DEBUG: scan before sanitize (cmd.exe / COMSPEC 等) ==="
# 残骸の場所を可視化
grep -nE 'cmd\.exe|COMSPEC|ComSpec|MP_SHELL|SHELL[[:space:]]*[:=][[:space:]]*cmd\.exe' -H *.mk || true

# すべての .mk を横断して置換
for f in *.mk; do
  # 改行は上で LF 統一済み

  # SHELL=cmd.exe の全書式を /bin/sh に
  sed -i -E 's|^SHELL[[:space:]]*[:=][[:space:]]*cmd\.exe|SHELL=/bin/sh|' "$f"

  # COMSPEC/ComSpec/MP_SHELL は無効化（残っていると間接参照される）
  sed -i -E 's|^(COMSPEC|ComSpec|MP_SHELL)[[:space:]]*[:=].*|# \1 disabled in CI|' "$f"

  # PATH は XC32/bin を先頭に（Windows PATH 行を潰す）
  if grep -q '^PATH:=' "$f"; then
    sed -i "s|^PATH:=.*|PATH:=${XC32_BIN}:\$(PATH)|" "$f"
  else
    printf 'PATH:=%s:$(PATH)\n' "${XC32_BIN}" >> "$f"
  fi

  # XC32 実行ファイル (Windows → Linux)
  sed -i \
    -e "s|^MP_CC[[:space:]]*[:=].*|MP_CC=${XC32_BIN}/xc32-gcc|" \
    -e "s|^MP_CPPC[[:space:]]*[:=].*|MP_CPPC=${XC32_BIN}/xc32-g++|" \
    -e "s|^MP_AS[[:space:]]*[:=].*|MP_AS=${XC32_BIN}/xc32-as|" \
    -e "s|^MP_LD[[:space:]]*[:=].*|MP_LD=${XC32_BIN}/xc32-ld|" \
    -e "s|^MP_AR[[:space:]]*[:=].*|MP_AR=${XC32_BIN}/xc32-ar|" \
    -e "s|^MP_CC_DIR[[:space:]]*[:=].*|MP_CC_DIR=${XC32_BIN}|" \
    -e "s|^MP_CPPC_DIR[[:space:]]*[:=].*|MP_CPPC_DIR=${XC32_BIN}|" \
    -e "s|^MP_AS_DIR[[:space:]]*[:=].*|MP_AS_DIR=${XC32_BIN}|" \
    -e "s|^MP_LD_DIR[[:space:]]*[:=].*|MP_LD_DIR=${XC32_BIN}|" \
    -e "s|^MP_AR_DIR[[:space:]]*[:=].*|MP_AR_DIR=${XC32_BIN}|" \
    "$f"

  # IDE/JAVA 依存は CI では無効化
  sed -i -E \
    -e 's|^PATH_TO_IDE_BIN[[:space:]]*[:=].*|# PATH_TO_IDE_BIN disabled in CI|' \
    -e 's|^MP_JAVA_PATH[[:space:]]*[:=].*|# MP_JAVA_PATH disabled in CI|' \
    -e 's|^DEP_GEN[[:space:]]*[:=].*|DEP_GEN=echo "Skipping dependency generation"|' \
    "$f"

  # Windows の CMSIS/DFP 絶対パスはコメントアウト（packs or 相対で解決）
  sed -i -E \
    -e 's|^CMSIS_DIR[[:space:]]*[:=].*|# CMSIS_DIR (set by project/packs)|' \
    -e 's|^DFP_DIR[[:space:]]*[:=].*|# DFP_DIR (set by project/packs)|' \
    "$f"
done

echo "=== DEBUG: scan after sanitize ==="
grep -nE 'cmd\.exe|COMSPEC|ComSpec|MP_SHELL|SHELL[[:space:]]*[:=][[:space:]]*cmd\.exe' -H *.mk || true

# 代表：適用対象（CONFIG）の先頭 120 行を出力して効き目確認
echo "=== DEBUG: head of ${NB_MK} ==="
sed -n '1,120p' "${NB_MK}"

popd >/dev/null

# 念のため環境変数でも SHELL を固定（Make が継承）
export SHELL=/bin/sh
unset COMSPEC || true
unset ComSpec || true

# XC32 を PATH に載せる / packs を環境へ（プロジェクト側が参照する場合に備える）
export PATH="${XC32_BIN}:${PATH}"
export DFP_PACKS="${PACKS}"

# -----------------------------------------------------------------------------
# 4) ビルド（ルート Makefile を直接呼ぶ -> 再帰ループなし）
# -----------------------------------------------------------------------------
if [[ ! -f "${ROOT_MK}" ]]; then
  echo "Error: root Makefile not found: ${ROOT_MK}"
  exit 3
fi

echo "=== Building with make (root Makefile) ==="
# 追跡ログを有効化して、どのルール/ファイルが使われたか可視化
make --no-builtin-rules --trace -C "${PROJECT_DIR}" CONF="${CONFIG}" build

echo "=== Build Completed Successfully ==="
