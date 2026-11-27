import 'package:flutter_test/flutter_test.dart';
import 'package:asetku/portfolio_math.dart';

void main() {
  group('Perhitungan transaksi portofolio', () {
    test('menghitung harga rata-rata tertimbang dari beberapa pembelian', () {
      final position = calculatePosition([
        PortfolioTransaction(type: 'buy', units: 2, unitPrice: 100, fee: 10),
        PortfolioTransaction(type: 'buy', units: 3, unitPrice: 120, fee: 10),
      ]);

      expect(position.units, 5);
      expect(position.costBasis, 580);
      expect(position.averageCost, 116);
      expect(position.totalBuyFees, 20);
    });

    test('penjualan mengurangi modal proporsional dan menghitung laba terealisasi', () {
      final position = calculatePosition([
        PortfolioTransaction(type: 'buy', units: 5, unitPrice: 100),
        PortfolioTransaction(type: 'sell', units: 2, unitPrice: 130, fee: 5),
      ]);

      expect(position.units, 3);
      expect(position.costBasis, 300);
      expect(position.averageCost, 100);
      expect(position.realizedProfitLoss, 55);
      expect(position.totalSellFees, 5);
    });

    test('menolak penjualan melebihi unit yang dimiliki', () {
      expect(
        () => calculatePosition([
          PortfolioTransaction(type: 'buy', units: 1, unitPrice: 100),
          PortfolioTransaction(type: 'sell', units: 2, unitPrice: 120),
        ]),
        throwsArgumentError,
      );
    });

    test('mengurutkan transaksi berdasarkan tanggal', () {
      final position = calculatePosition([
        PortfolioTransaction(
          type: 'sell', units: 1, unitPrice: 150,
          date: DateTime(2025, 2),
        ),
        PortfolioTransaction(
          type: 'buy', units: 2, unitPrice: 100,
          date: DateTime(2025, 1),
        ),
      ]);

      expect(position.units, 1);
      expect(position.realizedProfitLoss, 50);
    });
  });
}
