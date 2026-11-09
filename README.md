# Cove

Browser file untuk app yang terpasang, plus pembersih cache dan file sementara. Jalan di **iOS 26.0–26.7.2** dan **iOS 27.0–27.2**.

Ini bukan jailbreak. Akses container-nya lewat [worse_query](https://github.com/forcequitOS/worse_query) kalau App Group tersedia, dan lewat [bad_query](https://github.com/forcequitOS/bad_query) kalau tidak. Source keduanya ikut di repo ini dan tetap di bawah GPL-3.0.

## Tab

- **Apps** — daftar app yang terpasang, lalu browser `Documents`, `Library`, `Caches`, `Preferences`, dan `tmp`. Bisa lihat teks, gambar, dan plist, share, rename, hapus, bikin file/folder.
- **Cleaner** — ukur dan hapus isi `Library/Caches` dan `tmp` untuk app pihak ketiga. Documents tidak disentuh.

## Sign

Actions → Build IPA menghasilkan satu file unsigned: `Cove.ipa`. Sign dengan RustSign, sama seperti HouseArrest.

Sertifikat RustSign biasanya tidak membawa App Group `group.tr.sapu.cove`. Tanpa container itu `worse_query` tidak bisa jalan, jadi Cove lanjut pakai `bad_query` seperti HouseArrest.

Di iOS 26, query App Group pakai flag alternatif. Di luar rentang iOS di atas, Cove menolak jalan.

## Lisensi

GPL-3.0-or-later. Lihat [LICENSE](LICENSE).

`Cove/Exploit/worse_query.*` dan `pathleak.*` Copyright (C) 2026 Taj C (forcequit).
`Cove/Exploit/bad_query.*` dari [forcequitOS/bad_query](https://github.com/forcequitOS/bad_query).
