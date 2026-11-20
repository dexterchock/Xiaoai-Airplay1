#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-xiaoai-airplay1-toolchain:dev}"
SHAIRPORT_VERSION="5.6.3"
SHAIRPORT_SRC_DIR="${PROJECT_ROOT}/build/shairport-sync-src"
OUTPUT_BIN="${PROJECT_ROOT}/build/shairport-sync"
BUILD_STAMP="${PROJECT_ROOT}/build/.build-stamp"

EXPECTED_STAMP="$(sha256sum "${PROJECT_ROOT}/toolchain/Dockerfile" "${PROJECT_ROOT}/toolchain/build-shairport.sh" | sha256sum | awk '{print $1}')"

if [ "${FORCE_REBUILD:-0}" != "1" ] && [ -f "${OUTPUT_BIN}" ] && [ -f "${BUILD_STAMP}" ] && [ "$(cat "${BUILD_STAMP}")" = "${EXPECTED_STAMP}" ]; then
  echo "==> Up-to-date shairport-sync ${SHAIRPORT_VERSION} already exists at ${OUTPUT_BIN}, skipping build."
  exit 0
fi

make -C "${PROJECT_ROOT}/toolchain" IMAGE_NAME="${IMAGE_NAME}" build

mkdir -p "${PROJECT_ROOT}/build"

if [ -d "${SHAIRPORT_SRC_DIR}" ]; then
  CURRENT_TAG="$(git -C "${SHAIRPORT_SRC_DIR}" describe --tags --exact-match 2>/dev/null || true)"
  if [ "${CURRENT_TAG}" != "${SHAIRPORT_VERSION}" ]; then
    rm -rf "${SHAIRPORT_SRC_DIR}"
  fi
fi

if [ ! -d "${SHAIRPORT_SRC_DIR}" ]; then
  echo "==> Cloning shairport-sync ${SHAIRPORT_VERSION}..."
  git clone --depth 1 --branch "${SHAIRPORT_VERSION}" \
    https://github.com/mikebrady/shairport-sync.git "${SHAIRPORT_SRC_DIR}"
fi

echo "==> Building shairport-sync ${SHAIRPORT_VERSION} (ALSA + FFmpeg + SoXR + dns-sd) for OH2P..."
docker run --rm -i \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "${PROJECT_ROOT}":/workspace \
  -w /workspace/build/shairport-sync-src \
  "${IMAGE_NAME}" \
  bash << 'EOF'
set -euo pipefail

git config --global --add safe.directory "*"

autoreconf -fi

export PKG_CONFIG=/usr/local/bin/arm-pkg-config

./configure \
  --host=arm-buildroot-linux-gnueabihf \
  --sysconfdir=/data/xiaoai-airplay1 \
  --with-alsa \
  --with-dns_sd \
  --with-ssl=openssl \
  --with-ffmpeg \
  --with-soxr \
  CFLAGS="${OPT_FLAGS}" \
  LDFLAGS="--sysroot=${SYSROOT} -Wl,--as-needed -Wl,--gc-sections" \
  LIBS="-lm -lpthread -lrt -ldl"

make -j"$(nproc)"
${CROSS_PREFIX}strip --strip-unneeded shairport-sync

echo "==> Verifying ELF ABI compatibility for OH2P (armhf glibc <= 2.25)..."
${CROSS_PREFIX}readelf -h shairport-sync | grep -q "ELF32"
${CROSS_PREFIX}readelf -h shairport-sync | grep -q "Machine:.*ARM"

NEEDED="$(${CROSS_PREFIX}readelf -d shairport-sync | awk '/\(NEEDED\)/ {gsub(/[\[\]]/, "", $5); print $5}')"
echo "DT_NEEDED:"
echo "${NEEDED}"
ALLOWED_RE='^(libc\.so\.6|libm\.so\.6|libpthread\.so\.0|librt\.so\.1|libdl\.so\.2|libgcc_s\.so\.1|libasound\.so\.2|libdns_sd\.so|ld-linux-armhf\.so\.3)$'
for lib in ${NEEDED}; do
  if ! echo "${lib}" | grep -Eq "${ALLOWED_RE}"; then
    echo "ERROR: disallowed shared library dependency: ${lib}" >&2
    exit 1
  fi
done

GLIBC_VERS="$(${CROSS_PREFIX}readelf -V shairport-sync | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -u || true)"
echo "GLIBC symbol versions:"
echo "${GLIBC_VERS}"
if echo "${GLIBC_VERS}" | grep -Eq '^GLIBC_2\.(2[6-9]|[3-9][0-9])|^GLIBC_[3-9]\.'; then
  echo "ERROR: binary requires GLIBC > 2.25 (incompatible with OH2P glibc 2.25)" >&2
  exit 1
fi

cp shairport-sync /workspace/build/shairport-sync
EOF

echo "${EXPECTED_STAMP}" > "${BUILD_STAMP}"
echo "==> Built shairport-sync ${SHAIRPORT_VERSION} successfully: ${OUTPUT_BIN}"
ls -lh "${OUTPUT_BIN}"
