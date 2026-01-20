FROM ubuntu:22.04

ARG X32_VERSION=4.45
ARG DFP_PACKS=""
ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# -----------------------------------------------------
# APT を堅牢化（ミラー切替 + リトライ）
# -----------------------------------------------------
RUN set -eux; \
    try_update() { for i in 1 2 3; do apt-get update -qq && return 0 || sleep 5; done; return 1; }; \
    try_install() { for i in 1 2 3; do apt-get install -y -qq --no-install-recommends "$@" && return 0 || sleep 5; done; return 1; }; \
    if ! try_update; then \
      sed -i 's|http://archive.ubuntu.com|http://azure.archive.ubuntu.com|g' /etc/apt/sources.list; \
      if ! try_update; then \
        sed -i 's|http://azure.archive.ubuntu.com|http://mirrors.cloudflare.com/ubuntu|g' /etc/apt/sources.list; \
        try_update; \
      fi; \
    fi

# -----------------------------------------------------
# 必要ツール（最小限）
# -----------------------------------------------------
RUN try_install wget tar xz-utils libusb-1.0-0 make gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ（巨大インストーラ展開用）
RUN mkdir -p /work && chmod 777 /work

# -----------------------------------------------------
# XC32 (v4.45) を無人インストール
# -----------------------------------------------------
RUN wget -nv -O /work/xc32.run \
      "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc32-v${X32_VERSION}-full-install-linux-x64-installer.run" \
 && chmod +x /work/xc32.run \
 && /work/xc32.run \
      --mode unattended \
      --unattendedmodeui minimal \
      --agreeToLicense yes \
      --netservername localhost \
      --LicenseType FreeMode \
      --prefix "/opt/microchip/xc32/v${X32_VERSION}" \
 && rm -f /work/xc32.run

# -----------------------------------------------------
# DFP（packs）: 必要なら引数で渡す（CMSIS/SAMV71_DFP 等）
# ここでは値をログするのみ。実際の取得はCI側のアクション/スクリプトで行う想定。
# -----------------------------------------------------
RUN if [ -n "$DFP_PACKS" ]; then echo "DFP_PACKS=$DFP_PACKS"; fi

# ビルドスクリプト（プロジェクトに合わせて用意）
COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
