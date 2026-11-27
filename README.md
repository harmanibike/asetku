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
- [x] Validasi nama dan nominal aset/utang; format input Rupiah otomatis.
- [x] Edit dan hapus data aset/utang dengan konfirmasi.
- [x] Fondasi perhitungan transaksi beli/jual dengan harga rata-rata tertimbang.
- [x] Perhitungan biaya transaksi, modal tersisa, laba/rugi terealisasi, dan validasi unit penjualan.
- [ ] Form transaksi dan penyimpanan transaksi ke database SQLite.
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

## Perkembangan lanjutan
- Form aset dan utang mendukung mode tambah serta edit.
- Nominal input ditampilkan dengan pemisah ribuan Indonesia.
- Data hanya dapat dihapus setelah konfirmasi.
- Pengujian unit mencakup pembacaan nominal berformat Rupiah.
- Mesin hitung portofolio memproses transaksi beli/jual secara kronologis, memasukkan biaya ke modal pembelian, dan mengurangi modal secara proporsional saat penjualan.
- Penjualan yang melebihi unit tersedia ditolak agar posisi aset tidak menjadi negatif.
