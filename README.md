# xiaoai airplay1

High fidelity AirPlay 1 receiver (`shairport-sync` 5.6.3) built specifically for the Xiaomi Smart Speaker Pro (`OH2P`).

## Audio Pipeline Features

- **Native ALSA Output (`dsp` -> `dmixer`)**: Outputs 48 kHz 16-bit stereo directly through ALSA `pcm.dsp` at true unity gain, bypassing `mysoftvol` and `notifyvol` mixers and eliminating `aplay`.
- **FFmpeg ALAC & 48 kHz Resampling**: Uses FFmpeg `libavcodec` (ALAC) and `libswresample` for 44.1 kHz to 48 kHz conversion instead of the deprecated Hammerton decoder and ALSA `speexrate_medium`.
- **Real SoXR Sinc Interpolation**: Uses `libsoxr` (`interpolation = "soxr"`) with ALSA hardware delay feedback for active clock drift compensation and instant pause/seek flushing.
- **Native Apple mDNS (`dns-sd`)**: Registers through the speaker's built-in `/usr/bin/mdnsd` (`libdns_sd.so`) with automatic re-registration on Wi-Fi or `mdnsd` restart.
- **OH2P ABI Match**: Cross-compiled against `glibc 2.24` and Linux `4.9.30` headers with Cortex-A53 NEON tuning (`-mfpu=neon-vfpv4`, no `-ffast-math`), avoiding unsupported-syscall kernel log spam.
- **Dedicated CPU Window**: Runs under a self-healing supervisor at `nice -n -15` (`MALLOC_ARENA_MAX=2`), logs to `/tmp/shairport-sync.log` (tmpfs), and cleanly pauses/resumes `mipns-xiaomi` during active AirPlay sessions.

## Installation on Speaker

SSH into your Xiaomi Smart Speaker Pro (`OH2P`) and run:

```sh
curl -sSfL https://fastly.jsdelivr.net/gh/dexterchock/xiaoai-airplay1@main/install.sh | sh
```

Enable autostart on boot:

```sh
curl -sSfL -o /data/init.sh https://fastly.jsdelivr.net/gh/dexterchock/xiaoai-airplay1@main/boot.sh
chmod +x /data/init.sh
/data/init.sh
```

To require an AirPlay password, uncomment and set `password = "...";` in `/data/xiaoai-airplay1/shairport-sync.conf`, then run `/data/init.sh`.
