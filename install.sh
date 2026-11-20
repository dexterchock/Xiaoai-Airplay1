#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/data/xiaoai-airplay1}"
JSDELIVR_BASE="${JSDELIVR_BASE:-https://fastly.jsdelivr.net/gh/dexterchock/xiaoai-airplay1@cdn}"
GITHUB_BASE="${GITHUB_BASE:-https://github.com/dexterchock/xiaoai-airplay1/releases/latest/download}"
ARCHIVE_NAME="oh2p.tar.gz"
ARCHIVE_URL="${ARCHIVE_URL:-${JSDELIVR_BASE}/${ARCHIVE_NAME}}"
CHECKSUM_URL="${CHECKSUM_URL:-${JSDELIVR_BASE}/${ARCHIVE_NAME}.sha256}"
ARCHIVE_FALLBACK_URL="${ARCHIVE_FALLBACK_URL:-${GITHUB_BASE}/${ARCHIVE_NAME}}"
CHECKSUM_FALLBACK_URL="${CHECKSUM_FALLBACK_URL:-${GITHUB_BASE}/${ARCHIVE_NAME}.sha256}"
MIN_DATA_MB="${MIN_DATA_MB:-8}"
MIN_TMP_MB="${MIN_TMP_MB:-10}"

check_space() {
  dir="$1"
  min_mb="$2"
  probe="${dir}"
  while [ ! -d "${probe}" ]; do
    [ "${probe}" = "/" ] && break
    probe="$(dirname "${probe}")"
  done
  avail_kb="$(df -Pk "${probe}" 2>/dev/null | awk 'NR==2 {print $4}')"
  need_kb=$((min_mb * 1024))
  if [ -z "${avail_kb}" ] || [ "${avail_kb}" -lt "${need_kb}" ]; then
    echo "Error: insufficient disk space in ${probe} (need ${min_mb}MB)" >&2
    exit 1
  fi
}

download_and_verify() {
  pkg_url="$1"
  sum_url="$2"
  rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
  curl -fsSL --progress-bar "${pkg_url}" -o "${ARCHIVE_PATH}" || return 1
  curl -fsSL "${sum_url}" -o "${CHECKSUM_PATH}" || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "${TMP_DIR}" && sha256sum -c "$(basename "${CHECKSUM_PATH}")" >/dev/null) || return 1
  fi
  return 0
}

check_space "${APP_DIR}" "${MIN_DATA_MB}"
check_space "/tmp" "${MIN_TMP_MB}"

TMP_DIR="/tmp/xiaoai-airplay1-install.$$"
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${TMP_DIR}/${ARCHIVE_NAME}.sha256"
SRC_DIR="${TMP_DIR}/oh2p"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

mkdir -p "${TMP_DIR}" "${APP_DIR}"

echo "Downloading xiaoai-airplay1 package..."
if ! download_and_verify "${ARCHIVE_URL}" "${CHECKSUM_URL}"; then
  echo "Mirror failed or checksum mismatch, falling back to GitHub Release..." >&2
  if ! download_and_verify "${ARCHIVE_FALLBACK_URL}" "${CHECKSUM_FALLBACK_URL}"; then
    echo "Error: failed to download and verify ${ARCHIVE_NAME}" >&2
    exit 1
  fi
fi

tar -xzf "${ARCHIVE_PATH}" -C "${TMP_DIR}"

# Atomic binary install avoids ETXTBSY when upgrading a running daemon
cp "${SRC_DIR}/shairport-sync" "${APP_DIR}/shairport-sync.new"
chmod 0755 "${APP_DIR}/shairport-sync.new"
mv -f "${APP_DIR}/shairport-sync.new" "${APP_DIR}/shairport-sync"

if [ ! -f "${APP_DIR}/shairport-sync.conf" ]; then
  cp "${SRC_DIR}/shairport-sync.conf" "${APP_DIR}/shairport-sync.conf"
  chmod 0644 "${APP_DIR}/shairport-sync.conf"
elif ! cmp -s "${SRC_DIR}/shairport-sync.conf" "${APP_DIR}/shairport-sync.conf"; then
  cp "${SRC_DIR}/shairport-sync.conf" "${APP_DIR}/shairport-sync.conf.new"
  chmod 0644 "${APP_DIR}/shairport-sync.conf.new"
  echo "Note: kept existing ${APP_DIR}/shairport-sync.conf; new default saved to ${APP_DIR}/shairport-sync.conf.new"
fi

# Clean up obsolete files from earlier releases
rm -f "${APP_DIR}/volume-hook.sh" "${APP_DIR}/shairport.log" \
  /tmp/shairport-sync-metadata /tmp/airplay_pre_vol /tmp/airplay_last_vol

echo "Installation complete: ${APP_DIR}"
