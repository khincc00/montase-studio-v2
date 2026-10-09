#!/bin/bash
# Menjalankan semua test dan menyimpan laporan ke TestReports/ agar bisa ditinjau.
set -uo pipefail

cd "$(dirname "$0")/.."
REPORT_DIR="TestReports"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/test-report-$STAMP.txt"
FRAMES_SRC="$(getconf DARWIN_USER_TEMP_DIR)MontaseIT-frames"
FRAMES_DIR="$REPORT_DIR/frames-$STAMP"
mkdir -p "$REPORT_DIR"
# Hanya frame dari eksekusi ini yang disalin, agar tidak tercampur dengan hasil lama.
mkdir -p "$FRAMES_SRC" && rm -f "$FRAMES_SRC"/*.png

{
    echo "Montase Studio - laporan test"
    echo "Tanggal : $(date)"
    echo "Commit  : $(git rev-parse --short HEAD 2>/dev/null || echo '-')"
    echo "ffmpeg  : $(command -v /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg 2>/dev/null | head -1 || true)"
    echo
    swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^CoreData:"
} | tee "$REPORT"

echo
echo "Ringkasan:"
grep -E "Test Case .* (failed|skipped)|Executed [0-9]+ tests" "$REPORT" | tail -20
if compgen -G "$FRAMES_SRC/*.png" > /dev/null; then
    mkdir -p "$FRAMES_DIR" && cp "$FRAMES_SRC"/*.png "$FRAMES_DIR"/
    echo "Frame hasil render untuk ditinjau: $FRAMES_DIR ($(ls "$FRAMES_DIR" | wc -l | tr -d ' ') berkas)"
fi
echo "Laporan lengkap: $REPORT"
