FROM ubuntu:20.04

ARG MPLABX_VERSION=6.20
ARG X32_VERSION=4.45
ARG DFP_PACKS=""

ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# -----------------------------------------------------
# 1. Multiarch (i386) 有効化 + MPLAB X が必要とする 32bit ランタイムの追加
#    ※ Microchip の公式 Linux 要件に基づく（32bit ライブラリ必須）
# -----------------------------------------------------
RUN dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -y -qq \
      libc6:i386 \
      libstdc++6:i386 \
      zlib1g:i386 \
      libx11-6:i386 \
      libxext6:i386 \
      libxi6:i386 \
      libxtst6:i386 \
      libxrender1:i386 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------
# 2. 必須ツールのインストール
# -----------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y -qq \
        wget \
        tar \
        xz-utils \
        libusb-1.0-0 \
        make \
        gcc \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 作業領域 /work（InstallAnywhere が大量展開するため /tmp は使わない）
RUN mkdir -p /work && chmod -R 777 /work

# -----------------------------------------------------
# 3. MPLAB X IDE インストール
# -----------------------------------------------------
RUN wget -q --referer="https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide" \
      -O /work/MPLABX.tar \
      https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/MPLABX-v${MPLABX_VERSION}-linux-installer.tar \
    && cd /work \
    && tar -xf MPLABX.tar \
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
    && rm -f mplabx MPLABX.tar

# -----------------------------------------------------
# 4. XC32 コンパイラ インストール
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
# 5. DFP の追加インストール
# -----------------------------------------------------
RUN if [ -n "$DFP_PACKS" ]; then \
      chmod +x /opt/mplabx/mplab_platform/bin/packmanagercli.sh; \
      for p in $(echo "$DFP_PACKS" | tr "," "\n"); do \
        pn=$(echo "$p" | cut -d= -f1); \
        pv=$(echo "$p" | cut -d= -f2); \
        /opt/mplabx/mplab_platform/bin/packmanagercli.sh --install-pack "$pn" --version "$pv"; \
      done; \
    fi

# -----------------------------------------------------
# 6. ビルドスクリプト
# -----------------------------------------------------
COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
