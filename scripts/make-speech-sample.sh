#!/bin/bash
# Membuat audio ucapan Indonesia dengan jeda yang jelas untuk menguji Auto Clip.
# Memakai suara Damayanti dari macOS (say) dan ffmpeg. Hasil: ~/Movies/Montase Uji/ucapan-jeda.wav
set -euo pipefail

FFMPEG="$(command -v ffmpeg || true)"
[[ -n "$FFMPEG" ]] || { echo "ffmpeg tidak ditemukan. Pasang dengan: brew install ffmpeg"; exit 1; }

DIR="$HOME/Movies/Montase Uji"
WORK="$(mktemp -d)"
mkdir -p "$DIR"

say -v Damayanti -o "$WORK/s1.aiff" "Banyak pemula gagal karena tiga kesalahan ini."
say -v Damayanti -o "$WORK/s2.aiff" "Pertama, tidak riset produk yang sedang trending."
say -v Damayanti -o "$WORK/s3.aiff" "Kedua, asal sebar link tanpa cerita menarik."
say -v Damayanti -o "$WORK/s4.aiff" "Sekarang kita bahas modal kecil untuk pemula."
say -v Damayanti -o "$WORK/s5.aiff" "Modal kecil juga bisa menghasilkan uang asal tepat sasaran."

"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -t 1 -i anullsrc=r=22050:cl=mono -c:a pcm_s16le "$WORK/sil1.wav"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -t 3 -i anullsrc=r=22050:cl=mono -c:a pcm_s16le "$WORK/sil3.wav"
for n in 1 2 3 4 5; do
    "$FFMPEG" -hide_banner -loglevel error -y -i "$WORK/s$n.aiff" -ar 22050 -ac 1 -c:a pcm_s16le "$WORK/n$n.wav"
done
# Jeda 1 detik antarkalimat, dan jeda 3 detik sebagai batas topik.
printf "file '%s'\n" "$WORK/n1.wav" "$WORK/sil1.wav" "$WORK/n2.wav" "$WORK/sil1.wav" "$WORK/n3.wav" \
    "$WORK/sil3.wav" "$WORK/n4.wav" "$WORK/sil1.wav" "$WORK/n5.wav" > "$WORK/list.txt"
"$FFMPEG" -hide_banner -loglevel error -y -f concat -safe 0 -i "$WORK/list.txt" -c:a pcm_s16le "$DIR/ucapan-jeda.wav"

rm -rf "$WORK"
echo "Audio ucapan dibuat di: $DIR/ucapan-jeda.wav"
