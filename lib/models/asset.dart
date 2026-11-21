class Asset {
  const Asset({
    this.id,
    required this.name,
    required this.category,
    this.symbol,
    this.currency = 'IDR',
    this.quantity = 0,
    this.averageBuyPrice = 0,
    this.currentPrice = 0,
    this.notes,
    this.createdAt,
  });

  final int? id;
  final String name;
  final String category;
  final String? symbol;
  final String currency;
  final double quantity;
  final double averageBuyPrice;
  final double currentPrice;
  final String? notes;
  final String? createdAt;

  double get investedValue => quantity * averageBuyPrice;
  double get marketValue => quantity * currentPrice;
  double get unrealizedProfitLoss => marketValue - investedValue;
  double get returnPercentage =>
      investedValue == 0 ? 0 : (unrealizedProfitLoss / investedValue) * 100;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'symbol': symbol,
        'currency': currency,
        'quantity': quantity,
        'average_buy_price': averageBuyPrice,
        'current_price': currentPrice,
        'notes': notes,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
      };

  factory Asset.fromMap(Map<String, Object?> map) => Asset(
        id: map['id'] as int?,
        name: map['name'] as String,
        category: map['category'] as String,
        symbol: map['symbol'] as String?,
        currency: map['currency'] as String? ?? 'IDR',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        averageBuyPrice: (map['average_buy_price'] as num?)?.toDouble() ?? 0,
        currentPrice: (map['current_price'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String?,
      );
}
