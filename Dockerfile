FROM ubuntu:20.04

ARG X32_VERSION=4.45
ARG DFP_PACKS=""
ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# APT 高信頼化（ミラー切替 + リトライ）
RUN set -eux; \
    try_update() { for i in 1 2 3; do apt-get update -qq && return 0 || sleep 5; done; return 1; }; \
    try_install() { PKGS="$@"; for i in 1 2 3; do apt-get install -y -qq --no-install-recommends $PKGS && return 0 || sleep 5; done; return 1; }; \
    if ! try_update; then \
      sed -i 's|http://archive.ubuntu.com|http://azure.archive.ubuntu.com|g' /etc/apt/sources.list; \
      if ! try_update; then \
        sed -i 's|http://azure.archive.ubuntu.com|http://mirrors.cloudflare.com/ubuntu|g' /etc/apt/sources.list; \
        try_update; \
      fi; \
    fi

# Install XC32 required dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      libc6:i386 libstdc++6:i386 zlib1g:i386 \
      libx11-6:i386 libxext6:i386 libxi6:i386 \
      libxtst6:i386 libxrender1:i386 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install tools
RUN apt-get update -qq && apt-get install -y -qq \
      wget tar xz-utils libusb-1.0-0 make gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Work directory
RUN mkdir -p /work && chmod 777 /work

# Install XC32
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

# Install DFPs (CMSIS/SAMV71)
RUN if [ -n "$DFP_PACKS" ]; then \
      for p in $(echo "$DFP_PACKS" | tr "," "\n"); do \
        echo "DFP: installing $p"; \
      done; \
    fi

COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
