# Cove

Browser file untuk app yang terpasang, plus pembersih cache dan file sementara. Jalan di **iOS 26.0–26.7.2** dan **iOS 27.0–27.2**.

Ini bukan jailbreak. Akses container-nya lewat [worse_query](https://github.com/forcequitOS/worse_query). Daftar folder di iOS 27 lewat `fsgetpath`, sama seperti [WQFiles](https://github.com/kolbicz/WQFiles), karena folder induk tidak dapat token.

## Tab

- **Apps** — daftar app yang terpasang, lalu browser `Documents`, `Library`, `Caches`, `Preferences`, dan `tmp`. Bisa lihat teks, gambar, dan plist, share, rename, hapus, bikin file/folder.
- **Cleaner** — ukur dan hapus isi `Library/Caches` dan `tmp` untuk app pihak ketiga. Documents tidak disentuh.

## Sign

Actions → Build IPA menghasilkan satu file unsigned: `Cove.ipa`. Sign dengan RustSign.

Signer harus menyisakan sebuah App Group. Cove memakai group mana pun yang benar-benar masuk ke proses, bukan cuma `group.tr.sapu.cove`. Kalau signer membuang semua App Group, `worse_query` tidak bisa jalan. Log menulis group yang dipakai.

## Lisensi

GPL-3.0-or-later. Lihat [LICENSE](LICENSE).

`Cove/Exploit/worse_query.*` dan `pathleak.*` Copyright (C) 2026 Taj C (forcequit).
`Cove/Exploit/bad_query.*` dari [forcequitOS/bad_query](https://github.com/forcequitOS/bad_query).
