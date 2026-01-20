FROM ubuntu:20.04

ARG MPLABX_VERSION=6.20
ARG X32_VERSION=4.45
ARG DFP_PACKS=""
ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# -----------------------------------------------------
# 1) apt-get を高信頼化（ミラー切替 + リトライ）
# -----------------------------------------------------
RUN set -eux; \
    try_update() { for i in 1 2 3; do apt-get update -qq && return 0 || sleep 5; done; return 1; }; \
    try_install() { \
      PKGS="$@"; \
      for i in 1 2 3; do apt-get install -y -qq --no-install-recommends $PKGS && return 0 || sleep 5; done; \
      return 1; \
    }; \
    if ! try_update; then \
      sed -i 's|http://archive.ubuntu.com|http://azure.archive.ubuntu.com|g' /etc/apt/sources.list; \
      if ! try_update; then \
        sed -i 's|http://azure.archive.ubuntu.com|http://mirrors.cloudflare.com/ubuntu|g' /etc/apt/sources.list; \
        try_update; \
      fi; \
    fi

# -----------------------------------------------------
# 2) MPLAB X / XC32 に必須の 32bit ライブラリ（i386）を導入
#    ※Microchip 公式が “必須” と明記
# -----------------------------------------------------
RUN dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      libc6:i386 libstdc++6:i386 zlib1g:i386 \
      libx11-6:i386 libxext6:i386 libxi6:i386 \
      libxtst6:i386 libxrender1:i386 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------
# 3) 必要な 64bit ツール
# -----------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      wget tar xz-utils libusb-1.0-0 make gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Work directory (InstallAnywhere の巨大展開に必須)
RUN mkdir -p /work && chmod 777 /work

# -----------------------------------------------------
# 4) MPLAB X IDE インストール
# -----------------------------------------------------
RUN wget -q --referer="https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide" \
      -O /work/MPLABX.tar \
      https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/MPLABX-v${MPLABX_VERSION}-linux-installer.tar && \
    cd /work && \
    tar -xf MPLABX.tar && \
    mv MPLABX-v${MPLABX_VERSION}-linux-installer.sh mplabx && \
    chmod +x mplabx && \
    ./mplabx \
       --mode unattended \
       --unattendedmodeui minimal \
       --agreeToLicense yes \
       --ipe 0 \
       --collectInfo 0 \
       --installdir /opt/mplabx \
       --16bitmcu 0 --32bitmcu 1 --othermcu 0 && \
    rm -f mplabx MPLABX.tar

# -----------------------------------------------------
# 5) XC32 Compiler v4.45
# -----------------------------------------------------
RUN wget -nv -O /work/xc32.run \
      "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc32-v${X32_VERSION}-full-install-linux-x64-installer.run" && \
    chmod +x /work/xc32.run && \
    /work/xc32.run \
       --mode unattended \
       --unattendedmodeui minimal \
       --agreeToLicense yes \
       --netservername localhost \
       --LicenseType FreeMode \
       --prefix "/opt/microchip/xc32/v${X32_VERSION}" && \
    rm -f /work/xc32.run

# -----------------------------------------------------
# 6) DFP packs
# -----------------------------------------------------
RUN if [ -n "$DFP_PACKS" ]; then \
      chmod +x /opt/mplabx/mplab_platform/bin/packmanagercli.sh; \
      for p in $(echo "$DFP_PACKS" | tr "," "\n"); do \
        n=$(echo "$p" | cut -d= -f1); \
        v=$(echo "$p" | cut -d= -f2); \
        /opt/mplabx/mplab_platform/bin/packmanagercli.sh --install-pack "$n" --version "$v"; \
      done; \
    fi

COPY build.sh /build.sh
RUN chmod +x /build.sh
ENTRYPOINT ["/build.sh"]
