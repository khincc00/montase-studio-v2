# Montase Studio

Editor video native macOS (Swift 6.4 toolchain, SwiftUI, AVFoundation, Core Image), dibuat dari `blueprint-editor-macos.md`.

## Menjalankan

Butuh macOS 14+ dan Xcode 15+ (dikembangkan dengan Xcode 27).

```bash
open Package.swift   # buka di Xcode, lalu Run (⌘R)
swift test           # unit test + uji integrasi
```

Uji integrasi membuat media uji dengan ffmpeg (`/opt/homebrew/bin/ffmpeg` atau `/usr/local/bin/ffmpeg`). Tanpa ffmpeg, uji tersebut dilewati, bukan gagal.

## Fitur

- **Library:** impor (⌘I) atau seret file, pencarian, folder, thumbnail, relink media yang hilang, status proxy.
- **Timeline:** multitrack V/A dengan tambah dan hapus track, scroll vertikal dan horizontal, seret untuk pindah (dengan grup tautan), seret tepi untuk trim, snap ke playhead, marker, dan tepi clip.
- **Edit:** belah (S), hapus (⌫), hapus & rapatkan, duplikat, speed 0,25×–4×, fade masuk/keluar (dissolve sebagai fade di atas lapisan bawah), tautkan dan lepas, pisahkan audio ke track audio, tambah teks, undo/redo tak terbatas per sesi.
- **Transform dan warna:** posisi, skala, rotasi, crop (diterapkan sebelum rotasi), exposure, kontras, saturasi, suhu, tint, highlights, shadows, LUT `.cube` dengan intensitas, mode Sebelum/Sesudah, scope histogram.
- **Audio:** fader dan mute/solo per track, EQ tiga pita (low shelf 120 Hz, peaking 1 kHz, high shelf 8 kHz), meter dari puncak sumber di playhead, gelombang di clip.
- **Preview:** AVPlayer dengan compositor Core Image kustom; kualitas penuh, ½, atau ¼; proxy 960 px otomatis untuk sumber 4K.
- **Export:** 1080p atau 4K, landscape, portrait, atau square; H.264 atau HEVC; progres dan pembatalan.
- **Proyek:** simpan/buka `.montase` (JSON, penulisan atomik), autosave pemulihan, migrasi dari schema 1.
- **Lain-lain:** command palette (⌘K), workspace Edit / Color / Audio / Export (⌘1–⌘4), tekanan memori menjeda pembuatan proxy.

## Pintasan

| Aksi | Pintasan |
|---|---|
| Putar / jeda | Space |
| Belah pada playhead | S |
| Marker | M |
| Hapus clip | ⌫ (⇧⌫ lewat toolbar atau palette) |
| Frame sebelumnya / berikutnya | ← / → |
| Duplikat | ⌘D |
| Urungkan / ulangi | ⌘Z / ⇧⌘Z |
| Impor / buka / simpan | ⌘I / ⌘O / ⌘S |
| Command palette | ⌘K |
| Ekspor | ⌘E |

## Struktur

```
Sources/MontaseStudio/
  App/        AppState, entry point, menu
  Model/      Project, Track, Clip, MediaItem, Ticks (waktu integer 1/60.000 detik)
  Editing/    EditorStore (undo/redo, operasi timeline), penyimpanan proyek
  Media/      MediaImporter, ProxyManager, WaveformStore, LUTLoader
  Playback/   CompositionBuilder, EffectCompositor (Core Image), PlaybackController,
              ScopeStore, AudioEQ (MTAudioProcessingTap), BlankClip
  Export/     ExportController, Transcoder (AVAssetReader/Writer)
  UI/         Workspace, Library, Viewer, Timeline, Inspector, Color, Audio, Export, palette
Tests/MontaseStudioTests/
  ProjectEditingTests, FeatureTests          unit test model
  PipelineIntegrationTests                   ekspor end-to-end, proxy, teks-saja, performa
  FlashTimingTests, FrameLagTests            verifikasi timing dan warna export vs sumber
  UIRenderTests                              render setiap workspace (tanpa window)
```

## Catatan teknis penting

- Preview dan export memakai `EffectCompositor` yang sama. Compositor menerima buffer sumber tanpa konversi color space, dan `videoComposition` memakai tag warna sumber. Tanpa dua hal ini, nada tengah bergeser sekitar 11 level dari sumber (diverifikasi dengan flash abu-abu 128: sumber 141, export 141, preview 141).
- Durasi komposisi dijaga sama dengan durasi proyek lewat track filler, sehingga teks di ujung timeline tidak terpotong.

## Batasan yang masih ada

- Blueprint menyebut viewer Metal (`MTKView`). Implementasi memakai `AVPlayerView` dengan compositor Core Image di GPU; hasilnya setara untuk preview, tetapi bukan `MTKView` langsung.
- Format proyek berupa satu berkas JSON, bukan package `.frameproj` dengan folder `manifest.json`, `timeline.json`, dan `thumbnails/`.
- Dissolve antar clip pada track yang sama memakai fade masuk di atas lapisan bawah, bukan crossfade dengan handle media.
- Trim pada clip tertaut hanya mengubah clip yang dipilih; move, split, dan delete berlaku pada seluruh grup.
- EQ hanya tiga pita; tidak ada noise reduction atau voice isolation (sesuai blueprint, ditunda).
- Target performa blueprint belum diukur pada M1 8 GB. Pengukuran di Apple M4 16 GB: export timeline 31 detik 1080p H.264 dengan efek selesai dalam ±4,8 detik.
- Verifikasi GUI: render SwiftUI offscreen memastikan layout dibangun, tetapi isi di dalam `ScrollView` dan ikon SF Symbol tidak terlihat di render itu. Interaksi (drag, trim, pintasan) belum diuji dengan klik sungguhan karena screenshot layar tidak diizinkan di lingkungan ini.
- Timeline hanya-teks memakai klip hitam sementara sebagai sumber filler.
