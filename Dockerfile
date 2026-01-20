
FROM ubuntu:22.04

ARG X32_VERSION=4.45
ARG DFP_PACKS=""
ENV DEBIAN_FRONTEND=noninteractive
ENV TMPDIR=/work

# -----------------------------------------------------
# APT ミラー切替 + リトライ + 必須パッケージ
# -----------------------------------------------------
RUN set -eux; \
    try_update() { for i in 1 2 3; do apt-get update -y && return 0 || sleep 5; done; return 1; }; \
    try_install() { for i in 1 2 3; do apt-get install -y --no-install-recommends "$@" && return 0 || sleep 5; done; return 1; }; \
    if ! try_update; then \
      sed -i 's|http://archive.ubuntu.com|http://azure.archive.ubuntu.com|g' /etc/apt/sources.list; \
      if ! try_update; then \
        sed-i 's|http://azure.archive.ubuntu.com|http://mirrors.cloudflare.com/ubuntu|g' /etc/apt/sources.list; \
        try_update; \
      fi; \
    fi; \
    try_install \
      wget tar xz-utils libusb-1.0-0 make gcc \
      libx11-6 libxext6 libxrender1 libxi6 libxtst6 libxrandr2 \
      libgtk2.0-0 libglib2.0-0 ; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# InstallAnywhere の巨大展開用ディレクトリ
RUN mkdir -p /work && chmod 777 /work

# -----------------------------------------------------
# XC32 インストール (InstallAnywhere, 要 X11 libs)
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
# DFP packs
# -----------------------------------------------------
RUN if [ -n "$DFP_PACKS" ]; then echo "DFP_PACKS=$DFP_PACKS"; fi

COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
