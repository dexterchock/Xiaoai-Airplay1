![AirPlay for XiaoAi OH2P](assets/banner.png)

# Xiaoai Airplay1

AirPlay 1 receiver (`shairport-sync` 5.6.3) built for the Xiaomi Smart Speaker Pro (`OH2P`).

## Requirements

* Rooted Xiaomi Smart Speaker Pro (`OH2P`) with SSH enabled
* Local WiFi network

## Audio Pipeline and Runtime

* **Native ALSA output**: Streams 48 kHz 16 bit stereo straight to `pcm.dsp` and `pcm.dmixer` at unity gain, bypassing `mysoftvol` and `notifyvol` with no `aplay` pipe.
* **FFmpeg ALAC and resampling**: Decodes ALAC with `libavcodec` and resamples 44.1 kHz to 48 kHz via `libswresample` instead of the deprecated Hammerton decoder and ALSA `speexrate_medium`.
* **SoXR clock sync**: Uses `libsoxr` (`interpolation = "soxr"`) with ALSA hardware delay feedback for active clock drift compensation and clean pause/seek flushing.
* **Native Apple mDNS**: Registers directly through the speaker's built in `/usr/bin/mdnsd` (`libdns_sd.so`) and automatically restarts on `mdnsd` or WiFi IP changes.
* **OH2P ABI compatibility**: Cross compiled with Bootlin GCC 6.3, `glibc 2.24`, and Linux `4.9.30` headers with Cortex A53 NEON tuning (`-mfpu=neon-vfpv4`, no `-ffast-math`), avoiding unsupported syscall kernel log spam on Linux 4.9.61.
* **Volume behavior**: AirPlay volume runs inside `shairport-sync` using a 60 dB `dasl_tapered` curve with TPDF dither. Speaker top buttons stay independent and only adjust XiaoAi music, chimes, and alarms.
* **Low overhead supervisor**: Runs at `nice -n -15` (`MALLOC_ARENA_MAX=2`), logs to `/tmp/shairport-sync.log` in RAM, and pauses/resumes `mipns-xiaomi` cleanly around active AirPlay sessions.

## Installation

SSH into your `OH2P` speaker and install the package (verified with SHA256):

```sh
curl -sSfL https://fastly.jsdelivr.net/gh/dexterchock/xiaoai-airplay1@main/install.sh | sh
```

Enable autostart on boot and start the service:

```sh
curl -sSfL -o /data/init.sh https://fastly.jsdelivr.net/gh/dexterchock/xiaoai-airplay1@main/boot.sh
chmod +x /data/init.sh
/data/init.sh
```

## Configuration and Upgrades

* **Password**: Uncomment and set `password = "yourpass";` in `/data/xiaoai-airplay1/shairport-sync.conf`, then run `/data/init.sh`.
* **Upgrading**: Re run the install command above while the service is running. The binary replaces atomically, your existing `shairport-sync.conf` is preserved, and any updated defaults are written to `/data/xiaoai-airplay1/shairport-sync.conf.new`. Run `/data/init.sh` afterward to restart.
* **Logs**: Check `/tmp/shairport-sync.log` (automatically trimmed in RAM).

## Building from Source

Requires Docker on a Linux or WSL host:

```sh
make -C toolchain package
```

Outputs `dist/release/oh2p.tar.gz` and `dist/release/oh2p.tar.gz.sha256` after verifying ELF32 ARM `DT_NEEDED` and `glibc <= 2.25` symbol compatibility.
