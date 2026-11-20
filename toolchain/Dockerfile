# syntax=docker/dockerfile:1.4
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl git bzip2 xz-utils tar perl file \
      build-essential cmake ninja-build pkg-config \
      autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*

ENV TOOLCHAIN_DIR=/opt/toolchain
ENV SYSROOT=/opt/toolchain/arm-buildroot-linux-gnueabihf/sysroot
ENV PATH=/opt/toolchain/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV CROSS_PREFIX=arm-buildroot-linux-gnueabihf-
ENV OPT_FLAGS="-O3 -march=armv7-a -mtune=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard -ffunction-sections -fdata-sections"
ENV PKG_CONFIG_SYSROOT_DIR=/opt/toolchain/arm-buildroot-linux-gnueabihf/sysroot
ENV PKG_CONFIG_LIBDIR=/opt/toolchain/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/pkgconfig:/opt/toolchain/arm-buildroot-linux-gnueabihf/sysroot/usr/share/pkgconfig
ENV PKG_CONFIG_PATH=""

# pkg-config wrapper with --static for static transitive library resolution
RUN printf '#!/bin/sh\nexec /usr/bin/pkg-config --static "$@"\n' > /usr/local/bin/arm-pkg-config \
    && chmod 0755 /usr/local/bin/arm-pkg-config

# 1. Bootlin ARMv7-eabihf glibc 2.24 / Linux 4.9.30 / GCC 6.3.0 toolchain
RUN set -eu; \
    mkdir -p /tmp/deps "${TOOLCHAIN_DIR}"; \
    cd /tmp/deps; \
    curl -fsSL "https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/armv7-eabihf--glibc--bleeding-edge-2017.05-toolchains-1-2.tar.bz2" -o toolchain.tar.bz2; \
    echo "fa4223e8fd7841898b122740da096aa5b496706c1d17378c379afabdffd9f2b3  toolchain.tar.bz2" | sha256sum -c -; \
    tar -xjf toolchain.tar.bz2 --strip-components=1 -C "${TOOLCHAIN_DIR}"; \
    cd "${TOOLCHAIN_DIR}" && ./relocate-sdk.sh; \
    rm -rf /tmp/deps

# 2. ALSA 1.1.5 headers + link-time libasound.so.2 (matches speaker /usr/lib/libasound.so.2.0.0)
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://www.alsa-project.org/files/pub/lib/alsa-lib-1.1.5.tar.bz2" -o alsa-lib.tar.bz2; \
    echo "f4f68ad3c6da36b0b5241ac3c798a7a71e0e97d51f972e9f723b3f20a9650ae6  alsa-lib.tar.bz2" | sha256sum -c -; \
    tar -xjf alsa-lib.tar.bz2; \
    cd alsa-lib-1.1.5; \
    ./configure \
      --host=arm-buildroot-linux-gnueabihf \
      --prefix=/usr \
      --enable-shared \
      --disable-static \
      --disable-python \
      --disable-aload \
      --disable-rawmidi \
      --disable-hwdep \
      --disable-seq \
      --disable-ucm \
      --disable-topology \
      --disable-alisp \
      --disable-old-symbols \
      CFLAGS="${OPT_FLAGS}"; \
    make -j"$(nproc)"; \
    make DESTDIR="${SYSROOT}" install; \
    rm -f "${SYSROOT}"/usr/lib/*.la; \
    rm -rf /tmp/deps

# 3. Apple dns_sd.h + link-time libdns_sd.so stub (matches speaker /usr/lib/libdns_sd.so)
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://raw.githubusercontent.com/apple-oss-distributions/mDNSResponder/mDNSResponder-2881.120.11/mDNSShared/dns_sd.h" -o "${SYSROOT}/usr/include/dns_sd.h"; \
    echo "5d0ca50f207f6eb02e09d743f9b65d2ade65e8f81862dcd3703845b4fe87a9c1  ${SYSROOT}/usr/include/dns_sd.h" | sha256sum -c -; \
    printf '%s\n' \
      '#include <dns_sd.h>' \
      'DNSServiceErrorType DNSServiceRegister(DNSServiceRef *sdRef, DNSServiceFlags flags, uint32_t interfaceIndex, const char *name, const char *regtype, const char *domain, const char *host, uint16_t port, uint16_t txtLen, const void *txtRecord, DNSServiceRegisterReply callBack, void *context) { (void)sdRef;(void)flags;(void)interfaceIndex;(void)name;(void)regtype;(void)domain;(void)host;(void)port;(void)txtLen;(void)txtRecord;(void)callBack;(void)context; return 0; }' \
      'DNSServiceErrorType DNSServiceUpdateRecord(DNSServiceRef sdRef, DNSRecordRef RecordRef, DNSServiceFlags flags, uint16_t rdlen, const void *rdata, uint32_t ttl) { (void)sdRef;(void)RecordRef;(void)flags;(void)rdlen;(void)rdata;(void)ttl; return 0; }' \
      'void DNSServiceRefDeallocate(DNSServiceRef sdRef) { (void)sdRef; }' \
      > dns_sd_stub.c; \
    ${CROSS_PREFIX}gcc -shared -fPIC -Wl,-soname,libdns_sd.so -o "${SYSROOT}/usr/lib/libdns_sd.so" dns_sd_stub.c; \
    rm -rf /tmp/deps

# 4. Static libsoxr 0.1.3
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://deb.debian.org/debian/pool/main/libs/libsoxr/libsoxr_0.1.3.orig.tar.xz" -o soxr.tar.xz; \
    echo "b111c15fdc8c029989330ff559184198c161100a59312f5dc19ddeb9b5a15889  soxr.tar.xz" | sha256sum -c -; \
    mkdir src && tar -xJf soxr.tar.xz --strip-components=1 -C src; \
    cmake -S src -B build \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=arm \
      -DCMAKE_C_COMPILER=${CROSS_PREFIX}gcc \
      -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF \
      -DWITH_OPENMP=OFF \
      -DWITH_CR32S=OFF \
      -DWITH_CR64S=OFF \
      -DWITH_AVFFT=OFF \
      -DWITH_LSR_BINDINGS=OFF \
      -DBUILD_TESTS=OFF \
      -DBUILD_EXAMPLES=OFF; \
    cmake --build build -j"$(nproc)"; \
    DESTDIR="${SYSROOT}" cmake --install build; \
    rm -rf /tmp/deps

# 5. Static libconfig 1.7.3 + static popt 1.19
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://github.com/hyperrealm/libconfig/releases/download/v1.7.3/libconfig-1.7.3.tar.gz" -o libconfig.tar.gz; \
    echo "545166d6cac037744381d1e9cc5a5405094e7bfad16a411699bcff40bbb31ee7  libconfig.tar.gz" | sha256sum -c -; \
    tar -xzf libconfig.tar.gz; \
    cd libconfig-1.7.3; \
    ./configure \
      --host=arm-buildroot-linux-gnueabihf \
      --prefix=/usr \
      --enable-static \
      --disable-shared \
      --disable-cxx \
      --disable-examples \
      --disable-tests \
      --disable-doc \
      CFLAGS="${OPT_FLAGS}"; \
    make -j"$(nproc)"; \
    make DESTDIR="${SYSROOT}" install; \
    cd /tmp/deps; \
    curl -fsSL "https://deb.debian.org/debian/pool/main/p/popt/popt_1.19+dfsg.orig.tar.xz" -o popt.tar.xz; \
    echo "4cd0cd2963d0c4078f65949599d97135c15ee6c09cf3a36a9a1b2753025bb06b  popt.tar.xz" | sha256sum -c -; \
    mkdir popt-src && tar -xJf popt.tar.xz --strip-components=1 -C popt-src; \
    cd popt-src; \
    ./configure \
      --host=arm-buildroot-linux-gnueabihf \
      --prefix=/usr \
      --enable-static \
      --disable-shared \
      --disable-nls \
      CFLAGS="${OPT_FLAGS}"; \
    make -j"$(nproc)"; \
    make DESTDIR="${SYSROOT}" install; \
    rm -f "${SYSROOT}"/usr/lib/*.la; \
    rm -rf /tmp/deps

# 6. Static OpenSSL 3.0.22
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-3.0.22/openssl-3.0.22.tar.gz" -o openssl.tar.gz; \
    echo "67ebca7e50d17383028045486653492195b83db95f8558709701bb47b5c1ef81  openssl.tar.gz" | sha256sum -c -; \
    tar -xzf openssl.tar.gz; \
    cd openssl-3.0.22; \
    ./Configure linux-armv4 \
      --cross-compile-prefix="${CROSS_PREFIX}" \
      --prefix=/usr \
      --libdir=lib \
      no-shared no-apps no-docs no-tests no-dso no-engine no-legacy \
      no-dtls no-ssl3 no-tls1 no-tls1_1 no-comp \
      ${OPT_FLAGS}; \
    make -j"$(nproc)" build_libs; \
    make DESTDIR="${SYSROOT}" install_dev; \
    rm -rf /tmp/deps

# 7. Minimal static FFmpeg 6.1.2 (ALAC/PCM/AAC decoders + swresample for 44.1 -> 48 kHz)
RUN set -eu; \
    mkdir -p /tmp/deps && cd /tmp/deps; \
    curl -fsSL "https://ffmpeg.org/releases/ffmpeg-6.1.2.tar.xz" -o ffmpeg.tar.xz; \
    echo "3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38  ffmpeg.tar.xz" | sha256sum -c -; \
    tar -xJf ffmpeg.tar.xz; \
    cd ffmpeg-6.1.2; \
    ./configure \
      --enable-cross-compile \
      --cross-prefix="${CROSS_PREFIX}" \
      --target-os=linux \
      --arch=arm \
      --cpu=cortex-a53 \
      --enable-neon \
      --enable-vfp \
      --extra-cflags="${OPT_FLAGS}" \
      --prefix=/usr \
      --enable-static \
      --disable-shared \
      --disable-programs \
      --disable-doc \
      --disable-everything \
      --disable-network \
      --disable-autodetect \
      --enable-avcodec \
      --enable-avformat \
      --enable-avutil \
      --enable-swresample \
      --enable-decoder=alac \
      --enable-decoder=pcm_s16be \
      --enable-decoder=pcm_s16le \
      --enable-decoder=aac; \
    make -j"$(nproc)"; \
    make DESTDIR="${SYSROOT}" install; \
    rm -f "${SYSROOT}"/usr/lib/*.la; \
    rm -rf /tmp/deps

WORKDIR /workspace
CMD ["/bin/bash"]
