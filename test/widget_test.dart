import 'package:flutter_test/flutter_test.dart';
import 'package:asetku/main.dart';

void main() {
  group('Nominal Rupiah', () {
    test('mengurai nominal dengan pemisah ribuan', () {
      expect(parseNominal('1.250.000'), 1250000);
    });

    test('teks kosong atau karakter bukan angka menjadi nol', () {
      expect(parseNominal(''), 0);
      expect(parseNominal('Rp -'), 0);
    });

    test('format Rupiah menampilkan simbol mata uang', () {
      expect(rupiah(10000), contains('Rp'));
    });
  });
}
