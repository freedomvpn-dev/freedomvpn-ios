#!/bin/bash
# Builds the two native dependencies into Frameworks/ and downloads the geo files.
# Runs on macOS with Xcode, Go and Python 3 (GitHub Actions macos runner).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.deps"
mkdir -p "$WORK" "$ROOT/Frameworks" "$ROOT/PacketTunnel/Geo"

LIBXRAY_REF="${LIBXRAY_REF:-main}"
HEV_REF="${HEV_REF:-master}"

# LibXray.xcframework (Xray-core via gomobile; one Go runtime per process).
if [ ! -d "$ROOT/Frameworks/LibXray.xcframework" ]; then
  rm -rf "$WORK/libXray"
  git clone --depth 1 --branch "$LIBXRAY_REF" https://github.com/XTLS/libXray "$WORK/libXray"
  (cd "$WORK/libXray" && python3 build/main.py apple gomobile)
  cp -R "$WORK/libXray/LibXray.xcframework" "$ROOT/Frameworks/"
fi

# HevSocks5Tunnel.xcframework (C, static).
if [ ! -d "$ROOT/Frameworks/HevSocks5Tunnel.xcframework" ]; then
  rm -rf "$WORK/hev"
  git clone --depth 1 --recursive --branch "$HEV_REF" https://github.com/heiher/hev-socks5-tunnel "$WORK/hev"
  (cd "$WORK/hev" && ./build-apple.sh)
  cp -R "$WORK/hev/HevSocks5Tunnel.xcframework" "$ROOT/Frameworks/"
fi

# RoscomVPN geo files (same source as the Android app).
curl -fsSL -o "$ROOT/PacketTunnel/Geo/geosite.dat" \
  https://github.com/hydraponique/roscomvpn-geosite/releases/latest/download/geosite.dat
curl -fsSL -o "$ROOT/PacketTunnel/Geo/geoip.dat" \
  https://github.com/hydraponique/roscomvpn-geoip/releases/latest/download/geoip.dat
ls -la "$ROOT/Frameworks" "$ROOT/PacketTunnel/Geo"
