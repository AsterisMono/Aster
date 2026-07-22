FROM node:24.12.0-bookworm-slim AS node

RUN npm install -g typescript

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=node /usr/local /usr/local

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        binutils \
        bison \
        build-essential \
        bzip2 \
        ca-certificates \
        cpio \
        curl \
        dpkg-dev \
        elfutils \
        file \
        flex \
        git \
        gperf \
        libasound2-dev \
        libatspi2.0-dev \
        libbrlapi-dev \
        libbz2-dev \
        libcairo2-dev \
        libcap-dev \
        libcups2-dev \
        libcurl4-gnutls-dev \
        libdrm-dev \
        libelf-dev \
        libevdev-dev \
        libffi-dev \
        libgbm-dev \
        libglib2.0-dev \
        libglu1-mesa-dev \
        libgtk-3-dev \
        libinput-dev \
        libkrb5-dev \
        libnspr4-dev \
        libnss3-dev \
        libpam0g-dev \
        libpci-dev \
        libpulse-dev \
        libsctp-dev \
        libspeechd-dev \
        libsqlite3-dev \
        libssl-dev \
        libsystemd-dev \
        libudev-dev \
        libva-dev \
        libvulkan-dev \
        libwww-perl \
        libxkbcommon-dev \
        libxshmfence-dev \
        libxslt1-dev \
        libxss-dev \
        libxt-dev \
        libxtst-dev \
        lsb-release \
        mesa-common-dev \
        ninja-build \
        p7zip-full \
        patch \
        perl \
        pkg-config \
        python3 \
        python3-venv \
        rpm \
        unzip \
        uuid-dev \
        xz-utils \
        zip \
        zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /uc
ENTRYPOINT ["/bin/bash", "./scripts/package-rpm.sh"]
