class PortfolioTransaction {
  const PortfolioTransaction({
    required this.type,
    required this.units,
    required this.unitPrice,
    this.fee = 0,
    this.date,
  });

  final String type;
  final double units;
  final double unitPrice;
  final double fee;
  final DateTime? date;
}

class PortfolioPosition {
  const PortfolioPosition({
    required this.units,
    required this.costBasis,
    required this.averageCost,
    required this.realizedProfitLoss,
    required this.totalBuyFees,
    required this.totalSellFees,
  });

  final double units;
  final double costBasis;
  final double averageCost;
  final double realizedProfitLoss;
  final double totalBuyFees;
  final double totalSellFees;
}

PortfolioPosition calculatePosition(
  Iterable<PortfolioTransaction> transactions,
) {
  final ordered = transactions.toList()
    ..sort((a, b) => (a.date ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.date ?? DateTime.fromMillisecondsSinceEpoch(0)));

  var units = 0.0;
  var costBasis = 0.0;
  var realized = 0.0;
  var buyFees = 0.0;
  var sellFees = 0.0;

  for (final tx in ordered) {
    if (tx.units <= 0 || tx.unitPrice < 0 || tx.fee < 0) {
      throw ArgumentError('Unit harus positif; harga dan biaya tidak boleh negatif.');
    }
    if (tx.type == 'buy') {
      units += tx.units;
      costBasis += tx.units * tx.unitPrice + tx.fee;
      buyFees += tx.fee;
    } else if (tx.type == 'sell') {
      if (tx.units > units + 1e-9) {
        throw ArgumentError('Penjualan melebihi jumlah unit yang dimiliki.');
      }
      final averageBeforeSale = units == 0 ? 0.0 : costBasis / units;
      final allocatedCost = averageBeforeSale * tx.units;
      realized += tx.units * tx.unitPrice - tx.fee - allocatedCost;
      units -= tx.units;
      costBasis -= allocatedCost;
      sellFees += tx.fee;
      if (units.abs() < 1e-9) {
        units = 0;
        costBasis = 0;
      }
    } else {
      throw ArgumentError('Jenis transaksi harus buy atau sell.');
    }
  }

  return PortfolioPosition(
    units: units,
    costBasis: costBasis,
    averageCost: units == 0 ? 0 : costBasis / units,
    realizedProfitLoss: realized,
    totalBuyFees: buyFees,
    totalSellFees: sellFees,
  );
}
