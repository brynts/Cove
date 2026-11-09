# Cove

Browser file untuk app yang terpasang, plus pembersih cache dan file sementara. Jalan di **iOS 26.0–26.7.2** dan **iOS 27.0–27.2**.

Ini bukan jailbreak. Akses container-nya lewat [worse_query](https://github.com/forcequitOS/worse_query) (Taj C / forcequit, bareng 0xjohnny). Source exploit itu ikut di repo ini dan tetap di bawah GPL-3.0.

## Tab

- **Apps** — daftar app yang terpasang, lalu browser `Documents`, `Library`, `Caches`, `Preferences`, dan `tmp`. Bisa lihat teks, gambar, dan plist, share, rename, hapus, bikin file/folder.
- **Cleaner** — ukur dan hapus isi `Library/Caches` dan `tmp` untuk app pihak ketiga. Documents tidak disentuh.

## Syarat

Bundle ID `tr.sapu.cove`. Entitlement App Group wajib tetap ada setelah signing:

```xml
<key>com.apple.security.application-groups</key>
<array>
  <string>group.tr.sapu.cove</string>
</array>
```

ID yang sama ada di `Cove/CoveConfig.h`. Kalau diganti, ganti keduanya. Tanpa App Group, `worse_query` tidak bisa minta sandbox extension.

Di iOS 26, query App Group pakai flag alternatif. Container app pakai flag biasa. Di luar rentang iOS di atas, Cove menolak jalan.

## Build

Buka `Cove.xcodeproj` di Xcode dengan iOS 26 SDK, lalu pasang ke perangkat.

IPA unsigned (Actions → Build IPA, manual):

```bash
xcodebuild archive \
  -project Cove.xcodeproj \
  -scheme Cove \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Cove.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

Sign IPA-nya (enterprise, BrySign, atau tool lain) tanpa membuang entitlement App Group. Log on-device ada di sheet kaca pembesar di tab Apps.

## Lisensi

GPL-3.0-or-later. Lihat [LICENSE](LICENSE).

`Cove/Exploit/worse_query.*` dan `pathleak.*` Copyright (C) 2026 Taj C (forcequit).
