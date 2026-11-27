# Asetku

Aplikasi Android untuk mencatat aset, kewajiban, dan kekayaan bersih pribadi.

## Keputusan produk
- Gratis, tanpa lisensi, aktivasi, akun, atau login.
- Offline-first; data utama disimpan di SQLite pada perangkat.
- Rupiah (IDR) sebagai mata uang utama.
- Harga pasar otomatis bersifat opsional; input manual tetap tersedia.
- Backup dan pemulihan data lokal tersedia melalui file JSON; tidak memerlukan akun atau server.

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
- [x] Form transaksi beli/jual untuk emas, saham, reksadana, obligasi/SBN, dan crypto.
- [x] Penyimpanan transaksi di SQLite dengan migrasi aman dari database versi 1.
- [x] Riwayat transaksi, jumlah unit, harga rata-rata, modal tersisa, dan laba/rugi terealisasi.
- [x] Validasi agar transaksi jual tidak melebihi unit yang dimiliki.
- [x] Backup/restore JSON lokal dengan validasi format dan konfirmasi sebelum mengganti data.
- [x] Ringkasan alokasi aset per kategori dengan proporsi nilai.
- [x] Snapshot kekayaan bersih harian dan grafik riwayat hingga 30 catatan.
- [ ] Integrasi harga pasar dan kurs dengan fallback manual.
- [ ] Uji perangkat Android.

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
- Dashboard merangkum alokasi aset per kategori dan grafik riwayat kekayaan bersih; snapshot disimpan maksimal sekali per hari saat ringkasan dibuka.
- Detail investasi dapat dibuka dari daftar aset investasi; transaksi beli/jual tersimpan lokal dan riwayatnya dapat dilihat kembali.
- Migrasi database versi 1 ke versi 2 menambahkan tabel transaksi tanpa menghapus data aset/utang yang sudah ada.
- Nominal input ditampilkan dengan pemisah ribuan Indonesia.
- Data hanya dapat dihapus setelah konfirmasi.
- Pengujian unit mencakup pembacaan nominal berformat Rupiah.
- Mesin hitung portofolio memproses transaksi beli/jual secara kronologis, memasukkan biaya ke modal pembelian, dan mengurangi modal secara proporsional saat penjualan.
- Penjualan yang melebihi unit tersedia ditolak agar posisi aset tidak menjadi negatif.
