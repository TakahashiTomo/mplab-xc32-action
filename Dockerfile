FROM ubuntu:20.04

ARG MPLABX_VERSION=6.20
ARG X32_VERSION=4.45
ARG DFP_PACKS=""

ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# -----------------------------------------------------
# 基本パッケージ
# -----------------------------------------------------
RUN apt-get update -qq && apt-get install -y -qq \
    wget \
    tar \
    xz-utils \
    libusb-1.0-0 \
    make \
    gcc \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ
RUN mkdir -p /work && chmod -R 777 /work

# デバッグ（前段階）
RUN df -h

# -----------------------------------------------------
# MPLAB X IDE インストール（/tmp → /work）
# -----------------------------------------------------
RUN wget -q --referer="https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide" \
      -O /work/mplabx.tar \
      https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/MPLABX-v${MPLABX_VERSION}-linux-installer.tar \
    && cd /work \
    && tar -xf mplabx.tar \
    && mv MPLABX-v${MPLABX_VERSION}-linux-installer.sh mplabx \
    && chmod +x mplabx \
    && ./mplabx \
         --mode unattended \
         --unattendedmodeui minimal \
         --agreeToLicense yes \
         --ipe 0 \
         --collectInfo 0 \
         --installdir /opt/mplabx \
         --16bitmcu 0 --32bitmcu 1 --othermcu 0 \
    && rm -f mplabx mplabx.tar

# -----------------------------------------------------
# XC32 コンパイラ（巨大インストーラ → /work）
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

# デバッグ（インストール後）
RUN df -h && du -sh /opt/microchip/xc32 || true

# -----------------------------------------------------
# DFP インストール
# -----------------------------------------------------
RUN if [ -n "$DFP_PACKS" ]; then \
      echo "Installing DFPs: $DFP_PACKS"; \
      chmod +x /opt/mplabx/mplab_platform/bin/packmanagercli.sh; \
      for pack in $(echo "$DFP_PACKS" | tr "," "\n"); do \
        p_name=$(echo "$pack" | cut -d '=' -f 1); \
        p_ver=$(echo "$pack" | cut -d '=' -f 2); \
        /opt/mplabx/mplab_platform/bin/packmanagercli.sh --install-pack "$p_name" --version "$p_ver" > /dev/null 2>&1; \
      done; \
    fi

# -----------------------------------------------------
# ビルドスクリプト
# -----------------------------------------------------
COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
