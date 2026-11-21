class InvestmentTransaction {
  const InvestmentTransaction({
    this.id,
    required this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    this.fee = 0,
    this.tax = 0,
    required this.transactionDate,
    this.notes,
  });

  final int? id;
  final int assetId;
  /// BUY, SELL, DEPOSIT, WITHDRAW, DIVIDEND, INTEREST, COUPON, FEE, TAX
  final String type;
  final double quantity;
  final double price;
  final double fee;
  final double tax;
  final DateTime transactionDate;
  final String? notes;

  double get grossValue => quantity * price;
  double get netValue => grossValue + fee + tax;

  Map<String, Object?> toMap() => {
        'id': id,
        'asset_id': assetId,
        'type': type,
        'quantity': quantity,
        'price': price,
        'fee': fee,
        'tax': tax,
        'transaction_date': transactionDate.toIso8601String(),
        'notes': notes,
      };
}
