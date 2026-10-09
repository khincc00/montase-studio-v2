# Panduan pengujian manual

Dokumen ini untuk menguji Montase Studio langsung di Mac, lalu mencatat hasilnya. Setiap langkah punya hasil yang diharapkan. Tandai `[x]` jika sesuai, atau tulis catatan jika tidak.

## 0. Persiapan

1. Pasang ffmpeg: `brew install ffmpeg`.
2. Buat media uji: `./scripts/make-sample-media.sh`. File dibuat di `~/Movies/Montase Uji`.
3. Jalankan test otomatis: `./scripts/test.sh`. Laporan ada di `TestReports/test-report-*.txt`, dan frame hasil render ada di `TestReports/frames-*/`.
4. Bangun dan buka aplikasi: `./scripts/run-app.sh`.

## 1. Membuka dan proyek

- [ ] Aplikasi terbuka dengan jendela Edit, tanpa crash.
- [ ] ⌘N membuat proyek baru. Jika ada perubahan, muncul dialog "Simpan perubahan proyek?".
- [ ] ⌘S pada proyek baru membuka panel simpan. Simpan sebagai `uji.montase`.
- [ ] ⌘O membuka `uji.montase` kembali dan semua klip muncul.
- [ ] Membuka berkas `.montase` yang rusak (misal, isinya teks acak) menampilkan pesan gagal, tidak crash.

## 2. Autosave dan pemulihan

- [ ] Impor satu media, lalu tunggu sekitar 3 detik tanpa menyimpan. Tutup aplikasi dengan ⌘Q.
- [ ] Buka lagi aplikasi. Proyek terakhir muncul dengan status "Belum disimpan".
- [ ] Ulangi, tetapi setelah "Proyek Baru" pilih "Jangan Simpan", lalu tutup dan buka lagi. Proyek kosong tidak boleh membawa status "Belum disimpan" palsu.
- [ ] (Opsional) Rusakkan berkas pemulihan di `~/Library/Application Support/Montase Studio/recovery.montase`, lalu buka aplikasi. Harus muncul alert "Pemulihan gagal".

## 3. Library dan timeline

- [ ] ⌘I mengimpor `landscape-1080p.mp4`, `portrait-720x1280.mp4`, dan `musik-10s.m4a`. Thumbnail muncul.
- [ ] Dobel klik media menambahkannya ke timeline.
- [ ] Seret media ke track lain. Clip pindah, dan clip tidak bisa menimpa clip lain.
- [ ] Seret tepi clip untuk trim. Clip tidak bisa diperpanjang melewati awal atau akhir media.
- [ ] Tekan Space untuk memutar. Playhead bergerak dan video tampil di viewer.
- [ ] Letakkan playhead di tengah clip, lalu tekan S. Clip terbelah dua.
- [ ] ⌫ menghapus clip terpilih. ⇧⌫ menghapus dan merapatkan.
- [ ] ⌘D menduplikasi clip.
- [ ] ⌘Z dan ⇧⌘Z mengurungkan dan mengulang perubahan.
- [ ] Lakukan lebih dari 50 perubahan lalu ⌘Z berulang kali. Undo berhenti setelah 50 langkah.
- [ ] Tambah teks (menu Timeline). Teks muncul di viewer.
- [ ] Tambah marker dengan M.
- [ ] Ubah speed clip ke 2×. Durasi clip setengahnya.

## 4. Warna, audio, dan preview

- [ ] Workspace Color (⌘2): ubah exposure, kontras, saturasi, suhu. Preview berubah.
- [ ] Tombol Sebelum/Sesudah menampilkan sumber tanpa efek.
- [ ] Workspace Audio (⌘3): geser fader track dan EQ. Suara berubah saat diputar.
- [ ] Mute dan solo bekerja per track.
- [ ] Ganti kualitas preview ke ½ dan ¼. Playback tetap berjalan, dan gambar lebih kasar.
- [ ] Command palette (⌘K) menjalankan perintah dan menampilkan pintasannya.

## 5. Ekspor

- [ ] Workspace Export (⌘4), resolusi 1080p, landscape, H.264. Ekspor selesai dan nama file tanpa akhiran.
- [ ] Ekspor dengan orientasi Portrait. Nama berkas berakhiran `-vertikal`.
- [ ] Ekspor dengan orientasi Square. Nama berkas berakhiran `-persegi` (bukan `-vertikal`).
- [ ] Bandingkan ukuran berkas kualitas Standar dan Tinggi dari timeline yang sama. Tinggi harus lebih besar.
- [ ] Tombol Batalkan menghentikan ekspor, dan berkas parsial tidak tertinggal.
- [ ] Putar hasil ekspor di QuickTime. Video, audio, efek, dan teks ikut terekspor.

## 6. Media hilang dan relink

- [ ] Impor media, lalu pindahkan atau ganti nama filenya di Finder.
- [ ] Media ditandai "File hilang". Klik kanan, pilih Relink, lalu arahkan ke file baru. Clip kembali normal.

## 7. Antarmuka dan responsivitas

- [ ] Arahkan kursor ke ikon mana pun (misal tombol undo, scissors, flag). Setelah sekitar 0,4 detik muncul keterangan fungsi dengan pintasan, bukan tooltip bawaan macOS.
- [ ] Keterangan muncul di atas elemen, dan hilang saat kursor pergi. Tidak tertinggal di layar.
- [ ] Tombol ikon berubah latar saat disorot, dan mengecil sedikit saat ditekan.
- [ ] Tab Edit / Color / Audio / Export berpindah dengan animasi pada latar terpilih. ⌘1–⌘4 juga bekerja.
- [ ] Seret garis kecil di atas timeline untuk mengubah tinggi timeline. Tinggi tetap saat pindah workspace.
- [ ] Ubah ukuran jendela ke lebar minimum (sekitar 1100 px). Panel menyusut tanpa terpotong, dan toolbar timeline bisa digulir horizontal.
- [ ] Di Inspector, klik judul bagian untuk melipat atau membukanya. Klik dua kali label slider untuk mengembalikan nilai default (misal Volume kembali 100%).
- [ ] Di Library, arahkan kursor ke thumbnail. Ada sorotan dan bingkai aksen. Seret file ke area Library untuk mengimpor (bingkai putus-putus muncul saat file di atas panel).
- [ ] Timeline kosong menampilkan petunjuk. Setelah ada klip, petunjuk hilang.
- [ ] ⌘K membuka palet perintah. Panah atas-bawah memilih, Enter menjalankan, Esc menutup.
- [ ] Tombol Home kembali ke awal, Space memutar, ← dan → berpindah per frame.
- [ ] Slider (Inspector, Color, Audio): klik di jalur langsung melompat ke posisi itu. Seret mengikuti kursor. Tahan Shift saat menyeret untuk penyesuaian halus. Nilai ditampilkan saat diseret. Klik dua kali mengembalikan ke default. Bagian terisi berawal dari tanda netral.
- [ ] Workspace Export: kartu pengaturan memenuhi lebar kolom, pratinjau rasio berubah saat orientasi diganti, dan tombol Mulai Ekspor terlihat jelas.

## 8. Auto Clip

Persiapan: jalankan `./scripts/make-speech-sample.sh`. Ini membuat `~/Movies/Montase Uji/ucapan-jeda.wav`, yaitu ucapan Indonesia sungguhan (suara Damayanti) dengan jeda 1 detik antarkalimat dan 3 detik antartopik. Sumber tone di `make-sample-media.sh` tidak punya ucapan.

Izin: saat aplikasi pertama dibuka, macOS menanyakan izin "Pengenalan Ucapan". Pilih Izinkan. Pilihan ini bisa diubah di Pengaturan Sistem > Privasi & Keamanan > Pengenalan Ucapan.

Pemeriksaan cepat tanpa UI (dijalankan lewat `open` agar aplikasi yang meminta izin, bukan terminal):

    open -W "build/Montase Studio.app" --args --autoclip-check "$HOME/Movies/Montase Uji/ucapan-jeda.wav" --autoclip-out /tmp/autoclip-check.txt
    cat /tmp/autoclip-check.txt

Hasil yang diharapkan: `KATA` sekitar 30, `SUNYI` 4 (jeda 1 dan 3 detik), `TOPIK` 2, dan teks transkrip sesuai kalimat di atas.

- [ ] Tombol tongkat ajaib di bilah atas membuka panel Auto Clip. Perintah "Auto Clip…" juga ada di palet (⌘K).
- [ ] Pertama kali dijalankan, macOS meminta izin Pengenalan Ucapan. Setelah diizinkan, proses lanjut.
- [ ] Jika model offline bahasa Indonesia belum terpasang, muncul pesan yang menunjuk ke Pengaturan Sistem > Keyboard > Dikte. Pasang model itu lalu coba lagi.
- [ ] Setelah dijalankan, tahapan tampil berurutan: izin, salin audio, transkripsi, analisis, lalu ekspor per video.
- [ ] Tombol Batalkan menghentikan proses. Video yang sudah selesai tetap ada, dan tidak ada berkas setengah jadi di folder hasil.
- [ ] Folder hasil berisi `autoclip-analisis.json` dan file `01 Judul.mp4`, `02 Judul.mp4`, dan seterusnya.
- [ ] Buka `autoclip-analisis.json`. Strukturnya memakai `analisis_topik` dan `video_final_siap_posting`, dengan kunci sesuai spesifikasi.
- [ ] Setiap video final berdurasi 30–90 detik, kecuali yang diberi tanda "di bawah 30 detik". Setiap klip mentah 5 detik sampai 2 menit.
- [ ] Video hasil dimulai dengan hook, lalu isi, lalu penutup. Potongan selalu berhenti di akhir kalimat.
Pemeriksaan seluruh proses termasuk ekspor (tanpa UI):

    open -W "build/Montase Studio.app" --args --autoclip-run "/path/ke/video.mp4" --autoclip-out /tmp/autoclip-run.txt --autoclip-count 2

Jika gagal, `/tmp/autoclip-run.txt` menyebut tahap yang gagal dan kode error sistem, misalnya `Gagal pada tahap "Menyalin audio": Cannot Open [AVFoundationErrorDomain -11829]`. Jika penyebabnya codec, pesan juga menyarankan konversi ke MP4 H.264 + AAC.

- [ ] Tombol "Buka di editor" membuka hasil sebagai proyek. Klip sudah berurutan di track video dan bisa diatur ulang.
- [ ] Jika kamu menutup panel saat proses berjalan, proses tetap berjalan. Tombol tutup baru aktif setelah selesai.

## Catatan yang perlu diketahui saat meninjau

- `TestReports/frames-*/window-*.png` adalah render jendela sungguhan (isi timeline, Library, dan Inspector ikut tergambar). Ikon SF Symbol di sana bisa tampil sebagai kotak placeholder. Itu keterbatasan render offscreen, bukan bug aplikasi.
- `ui-*.png` adalah render cepat tanpa jendela; isi di dalam ScrollView tidak ikut tergambar di sana.
- Test integrasi dilewati jika ffmpeg tidak ditemukan. Laporan akan menampilkan jumlah test yang dilewati.
