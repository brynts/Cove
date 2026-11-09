# Cove

Browser file untuk app yang terpasang, plus pembersih cache dan file sementara. Jalan di **iOS 26.0–26.7.2** dan **iOS 27.0–27.2**.

Ini bukan jailbreak. Akses container-nya lewat [worse_query](https://github.com/forcequitOS/worse_query) (Taj C / forcequit, bareng 0xjohnny). Source exploit itu ikut di repo ini dan tetap di bawah GPL-3.0.

## Tab

- **Apps** — daftar app yang terpasang, lalu browser `Documents`, `Library`, `Caches`, `Preferences`, dan `tmp`. Bisa lihat teks, gambar, dan plist, share, rename, hapus, bikin file/folder.
- **Cleaner** — ukur dan hapus isi `Library/Caches` dan `tmp` untuk app pihak ketiga. Documents tidak disentuh.

## Syarat

Bundle ID `tr.sapu.cove`. `worse_query` butuh App Group `group.tr.sapu.cove` di signature IPA. ID yang sama ada di `Cove/CoveConfig.h` dan `Cove/Cove.entitlements`. Itu file build, bukan file yang di-upload terpisah.

HouseArrest tidak butuh ini karena dia pakai `bad_query`. `bad_query` sudah diganti `worse_query` di iOS 26/27, dan `worse_query` berhenti kalau container App Group-nya tidak ada.

Di iOS 26, query App Group pakai flag alternatif. Container app pakai flag biasa. Di luar rentang iOS di atas, Cove menolak jalan.

## Build

Actions → Build IPA. Hasilnya satu file: `Cove.ipa`. Sign dengan rustsign (p12), sama seperti HouseArrest. Jangan strip entitlement bawaan IPA.

Buka `Cove.xcodeproj` di Xcode kalau mau pasang langsung dari Mac.

Log on-device ada di sheet kaca pembesar di tab Apps.

## Lisensi

GPL-3.0-or-later. Lihat [LICENSE](LICENSE).

`Cove/Exploit/worse_query.*` dan `pathleak.*` Copyright (C) 2026 Taj C (forcequit).
