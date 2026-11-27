import 'package:flutter_test/flutter_test.dart';
import 'package:asetku/main.dart';

void main() {
  test('format Rupiah menampilkan simbol mata uang', () {
    expect(rupiah(10000), contains('Rp'));
  });
}
