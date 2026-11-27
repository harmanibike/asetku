# Asetku

Aplikasi Android untuk mencatat aset, kewajiban, dan kekayaan bersih pribadi.

## Keputusan produk
- Gratis, tanpa lisensi, aktivasi, akun, atau login.
- Offline-first; data utama disimpan di SQLite pada perangkat.
- Rupiah (IDR) sebagai mata uang utama.
- Harga pasar otomatis bersifat opsional; input manual tetap tersedia.
- Backup dan pemulihan data lokal menjadi fitur tahap berikutnya.

## Kategori aset
Emas, saham, reksadana, obligasi & SBN, crypto, kas & simpanan, properti, kendaraan, dan aset lainnya.

## Tahap 1
- [x] Struktur dasar Flutter dan navigasi.
- [x] Database SQLite untuk aset, utang, dan snapshot kekayaan.
- [x] Tambah/hapus aset dan kewajiban.
- [x] Ringkasan aset, utang, kekayaan bersih, dan untung/rugi terhadap modal.
- [x] GitHub Actions untuk analisis, pengujian, dan build APK.
- [ ] Validasi nominal dan format input Rupiah.
- [ ] Transaksi beli/jual dan metode perhitungan harga perolehan.
- [ ] Backup/restore JSON.
- [ ] Grafik riwayat dan alokasi portofolio.
- [ ] Integrasi harga pasar dan kurs dengan fallback manual.
- [ ] Uji build dan perangkat Android.

## Build
Workflow berjalan pada push ke `main`, pull request, atau manual melalui tab **Actions**. APK diunggah sebagai artifact `asetku-release-apk`.

Build lokal:
```bash
flutter create --platforms=android --org com.asetku --project-name asetku .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK release dari workflow belum ditandatangani dengan keystore produksi; gunakan untuk pengujian.
