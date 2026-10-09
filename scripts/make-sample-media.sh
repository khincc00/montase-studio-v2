#!/bin/bash
# Membuat media uji untuk pengujian manual di ~/Movies/Montase Uji.
# Membutuhkan ffmpeg (brew install ffmpeg).
set -euo pipefail

FFMPEG="$(command -v ffmpeg || true)"
[[ -n "$FFMPEG" ]] || { echo "ffmpeg tidak ditemukan. Pasang dengan: brew install ffmpeg"; exit 1; }

DIR="$HOME/Movies/Montase Uji"
mkdir -p "$DIR"

"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=1920x1080:rate=30" \
    -f lavfi -i "sine=frequency=440" -t 8 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$DIR/landscape-1080p.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=720x1280:rate=30" \
    -f lavfi -i "sine=frequency=880" -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$DIR/portrait-720x1280.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=330" -t 10 -c:a aac "$DIR/musik-10s.m4a"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=3840x2160:rate=30" \
    -t 5 -c:v libx264 -pix_fmt yuv420p -an "$DIR/uhd-4k-5s.mp4"

echo "Media uji dibuat di: $DIR"
ls -lh "$DIR"
