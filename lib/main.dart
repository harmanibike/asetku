import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'portfolio_math.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsetkuApp());
}

String rupiah(num value) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(value);

int parseNominal(String text) => int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final formatted = NumberFormat.decimalPattern('id_ID').format(int.parse(digits));
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;
  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'asetku.db'), version: 3, onCreate: (db, version) async {
      await db.execute('CREATE TABLE assets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, cost REAL NOT NULL, value REAL NOT NULL, created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE debts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, amount REAL NOT NULL, created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, assets REAL NOT NULL, debts REAL NOT NULL, net_worth REAL NOT NULL, recorded_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE asset_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL, type TEXT NOT NULL, units REAL NOT NULL, unit_price REAL NOT NULL, fee REAL NOT NULL DEFAULT 0, transaction_date TEXT NOT NULL, note TEXT NOT NULL, created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE market_prices (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL UNIQUE, unit_price REAL NOT NULL, source TEXT NOT NULL, updated_at TEXT NOT NULL)');
    }, onUpgrade: (db, oldVersion, newVersion) async { if (oldVersion < 2) await db.execute('CREATE TABLE asset_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL, type TEXT NOT NULL, units REAL NOT NULL, unit_price REAL NOT NULL, fee REAL NOT NULL DEFAULT 0, transaction_date TEXT NOT NULL, note TEXT NOT NULL, created_at TEXT NOT NULL)'); if (oldVersion < 3) await db.execute('CREATE TABLE market_prices (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL UNIQUE, unit_price REAL NOT NULL, source TEXT NOT NULL, updated_at TEXT NOT NULL)'); });
    return _db!;
  }
  Future<List<Map<String, Object?>>> list(String table) async => (await db).query(table, orderBy: 'id DESC');
  Future<void> addAsset(String name, String category, double cost, double value) async { await (await db).insert('assets', {'name': name, 'category': category, 'cost': cost, 'value': value, 'created_at': DateTime.now().toIso8601String()}); }
  Future<void> updateAsset(int id, String name, String category, double cost, double value) async {
    await (await db).update('assets', {'name': name, 'category': category, 'cost': cost, 'value': value}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> addDebt(String name, double amount) async { await (await db).insert('debts', {'name': name, 'amount': amount, 'created_at': DateTime.now().toIso8601String()}); }
  Future<void> updateDebt(int id, String name, double amount) async {
    await (await db).update('debts', {'name': name, 'amount': amount}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> addTransaction(int assetId, PortfolioTransaction tx, {String note = ''}) async {
    final d = await db;
    await d.transaction((txn) async {
      final asset = await txn.query('assets', columns: ['id'], where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (asset.isEmpty) throw ArgumentError('Aset tidak ditemukan.');
      final rows = await txn.query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date ASC, id ASC');
      final current = calculatePosition(rows.map((r) => PortfolioTransaction(type: r['type'] as String, units: (r['units'] as num).toDouble(), unitPrice: (r['unit_price'] as num).toDouble(), fee: (r['fee'] as num).toDouble(), date: DateTime.parse(r['transaction_date'] as String))));
      if (tx.type == 'sell' && tx.units > current.units + 1e-9) throw ArgumentError('Jumlah jual melebihi unit tersedia: ${current.units}');
      await txn.insert('asset_transactions', {'asset_id': assetId, 'type': tx.type, 'units': tx.units, 'unit_price': tx.unitPrice, 'fee': tx.fee, 'transaction_date': (tx.date ?? DateTime.now()).toIso8601String(), 'note': note, 'created_at': DateTime.now().toIso8601String()});
      final updatedRows = await txn.query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date ASC, id ASC');
      final position = calculatePosition(updatedRows.map((r) => PortfolioTransaction(type: r['type'] as String, units: (r['units'] as num).toDouble(), unitPrice: (r['unit_price'] as num).toDouble(), fee: (r['fee'] as num).toDouble(), date: DateTime.parse(r['transaction_date'] as String))));
      final market = await txn.query('market_prices', where: 'asset_id = ?', whereArgs: [assetId], limit: 1);
      final updates = <String, Object?>{'cost': position.costBasis};
      if (market.isNotEmpty) updates['value'] = position.units > 0 ? position.units * (market.first['unit_price'] as num).toDouble() : 0;
      await txn.update('assets', updates, where: 'id = ?', whereArgs: [assetId]);
    });
  }
  Future<List<Map<String, Object?>>> transactionsForAsset(int assetId) async => (await db).query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date DESC, id DESC');
  Future<Map<String, Object?>?> marketPriceForAsset(int assetId) async { final rows = await (await db).query('market_prices', where: 'asset_id = ?', whereArgs: [assetId], limit: 1); return rows.isEmpty ? null : rows.first; }
  Future<void> saveMarketPrice(int assetId, double price, {String source = 'manual'}) async {
    if (!price.isFinite || price < 0) throw ArgumentError('Harga pasar tidak valid.');
    final d = await db;
    await d.transaction((txn) async {
      final asset = await txn.query('assets', columns: ['id'], where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (asset.isEmpty) throw ArgumentError('Aset tidak ditemukan.');
      await txn.insert('market_prices', {'asset_id': assetId, 'unit_price': price, 'source': source, 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
      final rows = await txn.query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date ASC, id ASC');
      final position = calculatePosition(rows.map((r) => PortfolioTransaction(type: r['type'] as String, units: (r['units'] as num).toDouble(), unitPrice: (r['unit_price'] as num).toDouble(), fee: (r['fee'] as num).toDouble(), date: DateTime.parse(r['transaction_date'] as String))));
      if (rows.isNotEmpty) await txn.update('assets', {'value': position.units > 0 ? position.units * price : 0}, where: 'id = ?', whereArgs: [assetId]);
    });
  }
  Future<PortfolioPosition> positionForAsset(int assetId) async {
    final rows = await (await db).query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date ASC, id ASC');
    return calculatePosition(rows.map((r) => PortfolioTransaction(type: r['type'] as String, units: (r['units'] as num).toDouble(), unitPrice: (r['unit_price'] as num).toDouble(), fee: (r['fee'] as num).toDouble(), date: DateTime.parse(r['transaction_date'] as String))));
  }
  Future<void> delete(String table, int id) async {
    final d = await db;
    if (table == 'assets') { await d.delete('asset_transactions', where: 'asset_id = ?', whereArgs: [id]); await d.delete('market_prices', where: 'asset_id = ?', whereArgs: [id]); await d.delete('assets', where: 'id = ?', whereArgs: [id]); }
    if (table == 'debts') await d.delete('debts', where: 'id = ?', whereArgs: [id]);
  }
  Future<Map<String, Object?>> exportBackup() async {
    final d = await db;
    final assets = await d.query('assets', orderBy: 'id ASC');
    final debts = await d.query('debts', orderBy: 'id ASC');
    final snapshots = await d.query('snapshots', orderBy: 'id ASC');
    final transactions = await d.query('asset_transactions', orderBy: 'id ASC');
    final marketPrices = await d.query('market_prices', orderBy: 'id ASC');
    return {
      'app': 'Asetku',
      'schema_version': 3,
      'exported_at': DateTime.now().toIso8601String(),
      'assets': assets,
      'debts': debts,
      'snapshots': snapshots,
      'asset_transactions': transactions,
      'market_prices': marketPrices,
    };
  }

  Future<void> restoreBackup(Map<String, dynamic> backup) async {
    if (backup['app'] != 'Asetku' || backup['schema_version'] is! int ||
        (backup['schema_version'] as int) < 1 ||
        (backup['schema_version'] as int) > 3) {
      throw const FormatException('File bukan backup Asetku yang didukung.');
    }
    List<Map<String, Object?>> rows(String key) {
      final value = backup[key] ?? <dynamic>[];
      if (value is! List) throw FormatException('Data $key tidak valid.');
      return value.map((item) {
        if (item is! Map) throw FormatException('Baris $key tidak valid.');
        return Map<String, Object?>.from(item);
      }).toList();
    }
    final assets = rows('assets');
    final debts = rows('debts');
    final snapshots = rows('snapshots');
    final transactions = rows('asset_transactions');
    final marketPrices = rows('market_prices');
    for (final row in snapshots) {
      if (row['id'] is! num || row['assets'] is! num || row['debts'] is! num || row['net_worth'] is! num || row['recorded_at'] is! String) {
        throw const FormatException('Isi riwayat kekayaan tidak valid.');
      }
    }
    final marketPriceAssetIds = <Object?>{};
    for (final row in assets) {
      if (row['id'] is! num || row['name'] is! String ||
          row['category'] is! String || row['cost'] is! num ||
          row['value'] is! num || row['created_at'] is! String) {
        throw const FormatException('Isi data aset tidak lengkap.');
      }
    }
    for (final row in debts) {
      if (row['id'] is! num || row['name'] is! String ||
          row['amount'] is! num || row['created_at'] is! String) {
        throw const FormatException('Isi data utang tidak lengkap.');
      }
    }
    for (final row in transactions) {
      if (row['id'] is! num || row['asset_id'] is! num ||
          row['type'] is! String || !['buy', 'sell'].contains(row['type']) ||
          row['units'] is! num || (row['units'] as num) <= 0 ||
          row['unit_price'] is! num || (row['unit_price'] as num) < 0 ||
          row['fee'] is! num || (row['fee'] as num) < 0 ||
          row['transaction_date'] is! String ||
          row['note'] is! String || row['created_at'] is! String) {
        throw const FormatException('Isi riwayat transaksi tidak lengkap.');
      }
    }
    final assetIds = assets.map((row) => row['id']).toSet();
    for (final row in transactions) {
      if (!assetIds.contains(row['asset_id'])) {
        throw const FormatException('Riwayat transaksi merujuk aset yang tidak tersedia.');
      }
    }
    for (final row in marketPrices) {
      if (row['id'] is! num || row['asset_id'] is! num || !assetIds.contains(row['asset_id']) || row['unit_price'] is! num || (row['unit_price'] as num) < 0 || row['source'] is! String || row['updated_at'] is! String || !marketPriceAssetIds.add(row['asset_id'])) {
        throw const FormatException('Data harga pasar tidak valid atau duplikat.');
      }
    }
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('asset_transactions');
      await txn.delete('market_prices');
      await txn.delete('snapshots');
      await txn.delete('debts');
      await txn.delete('assets');
      for (final row in assets) {
        await txn.insert('assets', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in debts) {
        await txn.insert('debts', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in snapshots) {
        await txn.insert('snapshots', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in transactions) {
        await txn.insert('asset_transactions', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in marketPrices) {
        await txn.insert('market_prices', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<Map<String, Object?>> portfolioReport() async {
    final d = await db;
    final assets = await d.query('assets', orderBy: 'value DESC');
    final transactions = await d.rawQuery('SELECT t.*, a.name AS asset_name FROM asset_transactions t INNER JOIN assets a ON a.id = t.asset_id ORDER BY t.transaction_date DESC, t.id DESC');
    final grouped = <int, List<Map<String, Object?>>>{};
    for (final row in transactions) {
      final id = row['asset_id'] as int;
      grouped.putIfAbsent(id, () => []).add(row);
    }
    var realized = 0.0;
    var buyFees = 0.0;
    var sellFees = 0.0;
    var buyCount = 0;
    var sellCount = 0;
    final assetResults = <Map<String, Object?>>[];
    for (final asset in assets) {
      final id = asset['id'] as int;
      final rows = grouped[id] ?? <Map<String, Object?>>[];
      final position = calculatePosition(rows.map((r) => PortfolioTransaction(
        type: r['type'] as String,
        units: (r['units'] as num).toDouble(),
        unitPrice: (r['unit_price'] as num).toDouble(),
        fee: (r['fee'] as num).toDouble(),
        date: DateTime.parse(r['transaction_date'] as String),
      )));
      realized += position.realizedProfitLoss;
      buyFees += position.totalBuyFees;
      sellFees += position.totalSellFees;
      buyCount += rows.where((r) => r['type'] == 'buy').length;
      sellCount += rows.where((r) => r['type'] == 'sell').length;
      if (rows.isNotEmpty) {
        assetResults.add({
          'id': id,
          'name': asset['name'],
          'category': asset['category'],
          'realized': position.realizedProfitLoss,
          'units': position.units,
          'cost': position.costBasis,
          'value': (asset['value'] as num).toDouble(),
        });
      }
    }
    final totalValue = assets.fold<double>(0, (sum, r) => sum + (r['value'] as num).toDouble());
    final totalCost = assets.fold<double>(0, (sum, r) => sum + (r['cost'] as num).toDouble());
    final debts = await d.rawQuery('SELECT COALESCE(SUM(amount),0) AS total FROM debts');
    final totalDebts = (debts.first['total'] as num).toDouble();
    return {
      'asset_value': totalValue,
      'asset_cost': totalCost,
      'unrealized': totalValue - totalCost,
      'realized': realized,
      'buy_fees': buyFees,
      'sell_fees': sellFees,
      'fees': buyFees + sellFees,
      'buy_count': buyCount,
      'sell_count': sellCount,
      'transaction_count': buyCount + sellCount,
      'debts': totalDebts,
      'net_worth': totalValue - totalDebts,
      'assets': assetResults,
      'all_transactions': transactions,
    };
  }

  Future<List<Map<String, Object?>>> allocation() async {
    final d = await db;
    return d.rawQuery('SELECT category, SUM(value) AS total FROM assets GROUP BY category HAVING SUM(value) > 0 ORDER BY total DESC');
  }

  Future<List<Map<String, Object?>>> netWorthHistory() async {
    final d = await db;
    return d.query('snapshots', orderBy: 'recorded_at ASC', limit: 30);
  }

  Future<List<Object>> dashboardData() async {
    final summary = await totals();
    final categories = await allocation();
    final history = await netWorthHistory();
    return <Object>[summary, categories, history];
  }

  Future<Map<String, double>> totals() async {
    final d = await db;
    final a = await d.rawQuery('SELECT COALESCE(SUM(value),0) total, COALESCE(SUM(cost),0) cost FROM assets');
    final b = await d.rawQuery('SELECT COALESCE(SUM(amount),0) total FROM debts');
    final assets = (a.first['total'] as num).toDouble();
    final cost = (a.first['cost'] as num).toDouble();
    final debts = (b.first['total'] as num).toDouble();
    final now = DateTime.now();
    final latest = await d.query('snapshots', orderBy: 'recorded_at DESC', limit: 1);
    final lastDate = latest.isEmpty ? null : DateTime.tryParse(latest.first['recorded_at'] as String);
    if (lastDate == null || lastDate.year != now.year || lastDate.month != now.month || lastDate.day != now.day) {
      await d.insert('snapshots', {'assets': assets, 'debts': debts, 'net_worth': assets - debts, 'recorded_at': now.toIso8601String()});
    }
    return {'assets': assets, 'cost': cost, 'debts': debts, 'net': assets - debts, 'pnl': assets - cost};
  }
}

class AsetkuApp extends StatelessWidget {
  const AsetkuApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Asetku', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)), scaffoldBackgroundColor: const Color(0xFFF5F7FA)),
    home: const MainScreen(),
  );
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int tab = 0;
  int refresh = 0;
  void changed() => setState(() => refresh++);
  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(key: ValueKey('home$refresh'), changed: changed),
      Records(key: ValueKey('assets$refresh'), table: 'assets', changed: changed),
      Records(key: ValueKey('debts$refresh'), table: 'debts', changed: changed),
      const PortfolioReportPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.account_balance_wallet, color: Color(0xFF1769AA)), SizedBox(width: 9), Text('Asetku', style: TextStyle(fontWeight: FontWeight.w800))])),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Ringkasan'),
        NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Aset'),
        NavigationDestination(icon: Icon(Icons.credit_card_outlined), label: 'Utang'),
        NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'Laporan'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Pengaturan'),
      ]),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.changed});
  final VoidCallback changed;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object>>(
    future: LocalDb.instance.dashboardData(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final t = snapshot.data![0] as Map<String, double>;
      final categories = snapshot.data![1] as List<Map<String, Object?>>;
      final history = snapshot.data![2] as List<Map<String, Object?>>;
      final assets = t['assets']!;
      final debts = t['debts']!;
      final net = t['net']!;
      final pnl = t['pnl']!;
      final historyValues = history.map((r) => (r['net_worth'] as num).toDouble()).toList();
      return RefreshIndicator(onRefresh: () async => changed(), child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Ringkasan kekayaan', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1769AA), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kekayaan bersih', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(rupiah(net), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text('Total aset: ' + rupiah(assets), style: const TextStyle(color: Colors.white)),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Metric(title: 'Total aset', value: rupiah(assets), icon: Icons.savings_outlined)),
          const SizedBox(width: 10),
          Expanded(child: Metric(title: 'Total utang', value: rupiah(debts), icon: Icons.credit_card_outlined)),
        ]),
        const SizedBox(height: 10),
        Metric(title: 'Untung / rugi belum terealisasi', value: rupiah(pnl), icon: Icons.trending_up),
        const SizedBox(height: 18),
        const Text('Alokasi aset', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (categories.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Alokasi akan muncul setelah aset ditambahkan.')))
        else
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: categories.map((row) {
            final total = (row['total'] as num).toDouble();
            final ratio = assets <= 0 ? 0.0 : (total / assets).clamp(0.0, 1.0).toDouble();
            return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(row['category'] as String, style: const TextStyle(fontWeight: FontWeight.w600))), Text('${(ratio * 100).toStringAsFixed(1)}%  •  ${rupiah(total)}', style: const TextStyle(fontSize: 11))]),
              const SizedBox(height: 5),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: const Color(0xFFE8EDF3))),
            ]));
          }).toList()))),
        const SizedBox(height: 18),
        const Text('Riwayat kekayaan bersih', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: historyValues.length < 2
          ? const Text('Grafik akan terbentuk dari catatan harian. Buka ringkasan pada hari berbeda untuk merekam perkembangan.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(height: 150, width: double.infinity, child: CustomPaint(painter: NetWorthChartPainter(historyValues))),
              const SizedBox(height: 8),
              Text('Terakhir: ${rupiah(historyValues.last)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${history.length} catatan terakhir', style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
            ]))),
        const SizedBox(height: 20),
        const Text('Mulai mencatat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => assetDialog(context, changed), icon: const Icon(Icons.add), label: const Text('Tambah aset'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => debtDialog(context, changed), icon: const Icon(Icons.add), label: const Text('Tambah utang'))),
        ]),
        const SizedBox(height: 18),
        const Text('Aplikasi gratis tanpa akun dan lisensi. Data utama disimpan di perangkat dan dapat digunakan offline.', style: TextStyle(color: Color(0xFF667085), height: 1.4)),
      ]));
    },
  );
}

class NetWorthChartPainter extends CustomPainter {
  NetWorthChartPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    final line = Paint()..color = const Color(0xFF1769AA)..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final grid = Paint()..color = const Color(0xFFE8EDF3)..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[i] - minValue) / range;
      final y = size.height - normalized * (size.height - 12) - 6;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = const Color(0xFF1769AA);
    final lastY = size.height - (range == 0 ? 0.5 : (values.last - minValue) / range) * (size.height - 12) - 6;
    canvas.drawCircle(Offset(size.width, lastY), 4, dot);
  }

  @override
  bool shouldRepaint(covariant NetWorthChartPainter oldDelegate) => oldDelegate.values != values;
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.title, required this.value, required this.icon});
  final String title, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
    Icon(icon, color: const Color(0xFF1769AA)), const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
      const SizedBox(height: 4), Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ])),
  ])));
}

class PortfolioReportPage extends StatefulWidget {
  const PortfolioReportPage({super.key});
  @override
  State<PortfolioReportPage> createState() => _PortfolioReportPageState();
}

class _PortfolioReportPageState extends State<PortfolioReportPage> {
  int period = 0;

  DateTime? get periodStart {
    final now = DateTime.now();
    if (period == 30) return now.subtract(const Duration(days: 30));
    if (period == 90) return now.subtract(const Duration(days: 90));
    if (period == 365) return DateTime(now.year, 1, 1);
    return null;
  }

  List<Map<String, Object?>> filteredTransactions(List<Map<String, Object?>> rows) {
    final start = periodStart;
    if (start == null) return rows;
    return rows.where((row) {
      final date = DateTime.tryParse(row['transaction_date'] as String);
      return date != null && !date.isBefore(start);
    }).toList();
  }

  String csvCell(Object? value) {
    final valueText = value?.toString() ?? '';
    return '"${valueText.replaceAll('"', '""')}"';
  }

  Future<void> exportCsv(BuildContext context, Map<String, Object?> report,
      List<Map<String, Object?>> transactions) async {
    final rows = <List<Object?>>[
      ['LAPORAN ASETKU'],
      ['Diekspor', DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())],
      ['Periode transaksi', period == 0 ? 'Semua' : period == 365 ? 'Tahun berjalan' : '$period hari terakhir'],
      [],
      ['RINGKASAN KEKAYAAN (SEPANJANG WAKTU)'],
      ['Total nilai aset', report['asset_value']],
      ['Total modal aset', report['asset_cost']],
      ['Total utang', report['debts']],
      ['Kekayaan bersih', report['net_worth']],
      ['Laba/rugi terealisasi', report['realized']],
      ['Selisih nilai aset terhadap modal', report['unrealized']],
      ['Biaya beli', report['buy_fees']],
      ['Biaya jual', report['sell_fees']],
      [],
      ['RIWAYAT TRANSAKSI'],
      ['Tanggal', 'Aset', 'Jenis', 'Unit', 'Harga per unit', 'Biaya', 'Nilai transaksi', 'Catatan'],
    ];
    for (final tx in transactions) {
      final units = (tx['units'] as num).toDouble();
      final price = (tx['unit_price'] as num).toDouble();
      rows.add([tx['transaction_date'], tx['asset_name'], tx['type'] == 'buy' ? 'Beli' : 'Jual',
        units, price, tx['fee'], units * price, tx['note']]);
    }
    final csv = rows.map((row) => row.map(csvCell).join(';')).join('\r\n');
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Ekspor laporan Asetku',
        fileName: 'asetku_laporan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan CSV berhasil disimpan.')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor laporan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: LocalDb.instance.portfolioReport(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('Gagal memuat laporan: ${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final r = snapshot.data!;
      final assetRows = r['assets'] as List<Map<String, Object?>>;
      final allTransactions = r['all_transactions'] as List<Map<String, Object?>>;
      final recent = filteredTransactions(allTransactions);
      final realized = (r['realized'] as num).toDouble();
      final unrealized = (r['unrealized'] as num).toDouble();
      final fees = (r['fees'] as num).toDouble();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Laporan portofolio', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Ringkasan kinerja sepanjang waktu; filter berlaku untuk daftar dan ekspor transaksi.', style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            value: period,
            decoration: const InputDecoration(labelText: 'Periode transaksi', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Semua transaksi')),
              DropdownMenuItem(value: 30, child: Text('30 hari terakhir')),
              DropdownMenuItem(value: 90, child: Text('90 hari terakhir')),
              DropdownMenuItem(value: 365, child: Text('Tahun berjalan')),
            ],
            onChanged: (value) => setState(() => period = value ?? 0),
          )),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Ekspor CSV',
            onPressed: () => exportCsv(context, r, recent),
            icon: const Icon(Icons.file_download_outlined)),
        ]),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kekayaan bersih', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 5),
          Text(rupiah(r['net_worth'] as num), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1769AA))),
          const Divider(height: 22),
          positionLine('Total nilai aset', rupiah(r['asset_value'] as num)),
          positionLine('Total modal aset', rupiah(r['asset_cost'] as num)),
          positionLine('Total utang', rupiah(r['debts'] as num)),
        ]))),
        const SizedBox(height: 10),
        const Text('Kinerja investasi • sepanjang waktu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Metric(title: 'Laba/rugi terealisasi', value: rupiah(realized), icon: Icons.check_circle_outline)),
          const SizedBox(width: 10),
          Expanded(child: Metric(title: 'Selisih nilai aset terhadap modal', value: rupiah(unrealized), icon: Icons.trending_up)),
        ]),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          positionLine('Biaya beli', rupiah(r['buy_fees'] as num)),
          positionLine('Biaya jual', rupiah(r['sell_fees'] as num)),
          const Divider(),
          positionLine('Total biaya transaksi', rupiah(fees)),
          positionLine('Jumlah transaksi beli', (r['buy_count'] as int).toString()),
          positionLine('Jumlah transaksi jual', (r['sell_count'] as int).toString()),
        ]))),
        const SizedBox(height: 16),
        const Text('Kinerja per aset • sepanjang waktu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (assetRows.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada transaksi investasi.')))
        else
          ...assetRows.map((a) => Card(child: ListTile(
            title: Text(a['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${a['category']} • ${(a['units'] as num).toStringAsFixed(6)} unit'),
            trailing: Text(rupiah(a['realized'] as num), style: TextStyle(fontWeight: FontWeight.w700, color: (a['realized'] as num) >= 0 ? Colors.green : Colors.red)),
          ))),
        const SizedBox(height: 16),
        Text('Transaksi (${recent.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Tidak ada transaksi pada periode ini.')))
        else
          ...recent.take(100).map((tx) {
            final buy = tx['type'] == 'buy';
            final date = DateTime.tryParse(tx['transaction_date'] as String);
            final amount = (tx['units'] as num) * (tx['unit_price'] as num);
            return Card(child: ListTile(
              dense: true,
              leading: Icon(buy ? Icons.south_west : Icons.north_east, color: buy ? Colors.green : Colors.red),
              title: Text('${buy ? 'Beli' : 'Jual'} • ${tx['asset_name']} • ${tx['units']} unit'),
              subtitle: Text('${date == null ? '-' : DateFormat('dd MMM yyyy').format(date)} • ${tx['note']}'),
              trailing: Text(rupiah(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
            ));
          }),
        if (recent.length > 100)
          Padding(padding: const EdgeInsets.all(8), child: Text('Menampilkan 100 dari ${recent.length} transaksi. Ekspor CSV memuat semuanya.')),
        const SizedBox(height: 80),
      ]);
    },
  );
}

class Records extends StatelessWidget {
  const Records({super.key, required this.table, required this.changed});
  final String table;
  final VoidCallback changed;
  @override
  Widget build(BuildContext context) {
    final isAsset = table == 'assets';
    return FutureBuilder<List<Map<String, Object?>>>(
      future: LocalDb.instance.list(table),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        return Scaffold(backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(onPressed: () => isAsset ? assetDialog(context, changed) : debtDialog(context, changed), icon: const Icon(Icons.add), label: Text(isAsset ? 'Tambah aset' : 'Tambah utang')),
          body: !snapshot.hasData ? const Center(child: CircularProgressIndicator()) : rows.isEmpty
            ? Center(child: Text(isAsset ? 'Belum ada aset. Tambahkan aset pertama.' : 'Belum ada utang.'))
            : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: rows.length, itemBuilder: (context, i) {
              final row = rows[i];
              final amount = row[isAsset ? 'value' : 'amount'] as num;
              final subtitle = isAsset ? (row['category'] as String) + ' • Modal ' + rupiah(row['cost'] as num) : 'Kewajiban';
              return Card(child: ListTile(
                leading: CircleAvatar(child: Icon(isAsset ? Icons.account_balance_wallet_outlined : Icons.credit_card_outlined)),
                onTap: isAsset && ['Emas', 'Saham', 'Reksadana', 'Obligasi & SBN', 'Crypto'].contains(row['category']) ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailPage(asset: row, changed: changed))) : null,
                title: Text(row['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(subtitle), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(rupiah(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        if (isAsset) {
                          await assetDialog(context, changed, existing: row);
                        } else {
                          await debtDialog(context, changed, existing: row);
                        }
                      } else if (v == 'delete') {
                        final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: const Text('Hapus data?'),
                          content: Text('Data "${row['name']}" akan dihapus dari perangkat.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
                          ],
                        ));
                        if (confirm == true) {
                          await LocalDb.instance.delete(table, row['id'] as int);
                          changed();
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ),
                ]),
              ));
            }),
        );
      },
    );
  }
}

class AssetDetailPage extends StatefulWidget {
  const AssetDetailPage({super.key, required this.asset, required this.changed});
  final Map<String, Object?> asset;
  final VoidCallback changed;
  @override State<AssetDetailPage> createState() => _AssetDetailPageState();
}
class _AssetDetailPageState extends State<AssetDetailPage> {
  int revision = 0;
  @override Widget build(BuildContext context) {
    final id = widget.asset['id'] as int;
    return Scaffold(appBar: AppBar(title: Text(widget.asset['name'] as String)),
      floatingActionButton: FloatingActionButton.extended(onPressed: () async { await transactionDialog(context, id); if (mounted) setState(() => revision++); widget.changed(); }, icon: const Icon(Icons.add), label: const Text('Transaksi')),
      body: FutureBuilder<List<Object?>>(key: ValueKey(revision), future: Future.wait<Object?>([LocalDb.instance.positionForAsset(id), LocalDb.instance.transactionsForAsset(id), LocalDb.instance.marketPriceForAsset(id)]), builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final p = s.data![0] as PortfolioPosition; final rows = s.data![1] as List<Map<String, Object?>>; final market = s.data![2] as Map<String, Object?>?;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Posisi investasi', style: TextStyle(fontWeight: FontWeight.w800)),
            positionLine('Jumlah unit', p.units.toStringAsFixed(6)), positionLine('Harga rata-rata', rupiah(p.averageCost)), positionLine('Modal tersisa', rupiah(p.costBasis)), positionLine('Laba/rugi terealisasi', rupiah(p.realizedProfitLoss)),
            if (market != null) positionLine('Harga pasar terakhir', rupiah(market['unit_price'] as num)),
            if (market != null) positionLine('Nilai estimasi', rupiah(p.units * (market['unit_price'] as num))),
            if (market != null) positionLine('Sumber / diperbarui', '${market['source']} • ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(market['updated_at'] as String))}'),
          ]))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () async { await marketPriceDialog(context, id); if (mounted) setState(() => revision++); widget.changed(); }, icon: const Icon(Icons.price_change_outlined), label: const Text('Perbarui harga pasar manual')),
          const SizedBox(height: 12), const Text('Riwayat transaksi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (rows.isEmpty) const Text('Belum ada transaksi beli atau jual.'),
          ...rows.map((r) { final buy = r['type'] == 'buy'; return Card(child: ListTile(leading: Icon(buy ? Icons.south_west : Icons.north_east, color: buy ? Colors.green : Colors.red), title: Text((buy ? 'Beli ' : 'Jual ') + r['units'].toString()), subtitle: Text(DateFormat('dd MMM yyyy').format(DateTime.parse(r['transaction_date'] as String)) + ' • ' + (r['note'] as String)), trailing: Text(rupiah((r['units'] as num) * (r['unit_price'] as num))))); }),
          const SizedBox(height: 80),
        ]);
      }));
  }
}
Widget positionLine(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w700))]));
Future<void> marketPriceDialog(BuildContext context, int assetId) async {
  final existing = await LocalDb.instance.marketPriceForAsset(assetId);
  final controller = TextEditingController(text: existing == null ? '' : NumberFormat.decimalPattern('id_ID').format((existing['unit_price'] as num).round()));
  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('Perbarui harga pasar'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Masukkan harga per unit. Jika sudah ada transaksi beli/jual, nilai aset dihitung dari jumlah unit × harga ini.'),
      TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Harga per unit (Rp)')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
      FilledButton(onPressed: () { if (parseNominal(controller.text) <= 0) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Harga harus lebih dari nol.'))); return; } Navigator.pop(ctx, true); }, child: const Text('Simpan')),
    ],
  ));
  if (ok == true) await LocalDb.instance.saveMarketPrice(assetId, parseNominal(controller.text).toDouble());
  controller.dispose();
}

Future<void> transactionDialog(BuildContext context, int assetId) async {
  final units = TextEditingController(), price = TextEditingController(), fee = TextEditingController(text: '0'), note = TextEditingController();
  String type = 'buy'; final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
    title: const Text('Catat transaksi'),
    content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'buy', label: Text('Beli')), ButtonSegment(value: 'sell', label: Text('Jual'))], selected: {type}, onSelectionChanged: (v) => setLocal(() => type = v.first)),
      TextFormField(controller: units, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Jumlah unit'), validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Jumlah unit tidak valid' : null),
      TextFormField(controller: price, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Harga per unit (Rp)'), validator: (v) => parseNominal(v ?? '') <= 0 ? 'Harga wajib diisi' : null),
      TextField(controller: fee, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Biaya transaksi (Rp)')),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Simpan'))],
  )));
  if (ok == true) {
    final tx = PortfolioTransaction(type: type, units: double.parse(units.text.replaceAll(',', '.')), unitPrice: parseNominal(price.text).toDouble(), fee: parseNominal(fee.text).toDouble(), date: DateTime.now());
    try {
      if (type == 'sell') { final current = await LocalDb.instance.positionForAsset(assetId); if (tx.units > current.units + 1e-9) throw ArgumentError('Jumlah jual melebihi unit tersedia: ' + current.units.toString()); }
      await LocalDb.instance.addTransaction(assetId, tx, note: note.text.trim());
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('ArgumentError: ', '')))); }
  }
  units.dispose(); price.dispose(); fee.dispose(); note.dispose();
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> createBackup(BuildContext context) async {
    try {
      final data = await LocalDb.instance.exportBackup();
      final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan backup Asetku',
        fileName: 'asetku_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path != null) message(context, 'Backup berhasil disimpan.');
    } catch (e) {
      message(context, 'Gagal membuat backup: $e');
    }
  }

  Future<void> restoreBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih file backup Asetku',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) throw const FormatException('File tidak dapat dibaca.');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Struktur file backup tidak valid.');
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pulihkan backup?'),
          content: const Text('Data aset, utang, dan transaksi saat ini akan diganti dengan isi backup. Sebaiknya buat backup terbaru terlebih dahulu.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pulihkan')),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
      await LocalDb.instance.restoreBackup(decoded);
      if (context.mounted) message(context, 'Pemulihan data berhasil.');
    } catch (e) {
      if (context.mounted) message(context, 'Gagal memulihkan backup: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Pengaturan', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
    const SizedBox(height: 12),
    const Card(child: ListTile(leading: Icon(Icons.storage_outlined), title: Text('Database lokal'), subtitle: Text('Data tersimpan di perangkat menggunakan SQLite.'))),
    Card(child: ListTile(
      leading: const Icon(Icons.backup_outlined),
      title: const Text('Buat backup JSON'),
      subtitle: const Text('Simpan aset, utang, saldo nilai, dan riwayat transaksi ke file.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => createBackup(context),
    )),
    Card(child: ListTile(
      leading: const Icon(Icons.restore_outlined),
      title: const Text('Pulihkan backup JSON'),
      subtitle: const Text('Impor file backup dan ganti data lokal setelah konfirmasi.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => restoreBackup(context),
    )),
    const Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('Mode offline'), subtitle: Text('Pencatatan tetap berjalan tanpa internet.'))),
    const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Tentang Asetku'), subtitle: Text('Gratis • Tanpa akun • Tanpa lisensi'))),
  ]);
}

Future<void> assetDialog(BuildContext context, VoidCallback changed, {Map<String, Object?>? existing}) async {
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  final cost = TextEditingController(text: existing == null ? '' : NumberFormat.decimalPattern('id_ID').format((existing['cost'] as num).round()));
  final value = TextEditingController(text: existing == null ? '' : NumberFormat.decimalPattern('id_ID').format((existing['value'] as num).round()));
  String category = existing?['category'] as String? ?? 'Kas & Simpanan';
  const categories = ['Emas', 'Saham', 'Reksadana', 'Obligasi & SBN', 'Crypto', 'Kas & Simpanan', 'Properti', 'Kendaraan', 'Aset Lainnya'];
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, localSet) => AlertDialog(
    title: Text(existing == null ? 'Tambah aset' : 'Edit aset'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama aset')),
      DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Kategori'), items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => localSet(() => category = v ?? category)),
      TextField(controller: cost, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Total modal (Rp)')),
      TextField(controller: value, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Nilai saat ini (Rp)')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
      FilledButton(onPressed: () {
        final modal = parseNominal(cost.text);
        final nilai = parseNominal(value.text);
        if (name.text.trim().isEmpty || nilai <= 0) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama dan nilai aset wajib diisi dengan benar.')));
          return;
        }
        if (modal < 0) return;
        Navigator.pop(ctx, true);
      }, child: const Text('Simpan')),
    ],
  )));
  if (ok == true) {
    final modal = parseNominal(cost.text).toDouble();
    final nilai = parseNominal(value.text).toDouble();
    if (existing == null) {
      await LocalDb.instance.addAsset(name.text.trim(), category, modal, nilai);
    } else {
      await LocalDb.instance.updateAsset(existing['id'] as int, name.text.trim(), category, modal, nilai);
    }
    changed();
  }
  name.dispose(); cost.dispose(); value.dispose();
}

Future<void> debtDialog(BuildContext context, VoidCallback changed, {Map<String, Object?>? existing}) async {
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  final amount = TextEditingController(text: existing == null ? '' : NumberFormat.decimalPattern('id_ID').format((existing['amount'] as num).round()));
  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: Text(existing == null ? 'Tambah utang' : 'Edit utang'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama utang / kewajiban')),
      TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Jumlah (Rp)')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
      FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || parseNominal(amount.text) <= 0) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama dan jumlah utang wajib diisi dengan benar.')));
          return;
        }
        Navigator.pop(ctx, true);
      }, child: const Text('Simpan')),
    ],
  ));
  if (ok == true) {
    final nominal = parseNominal(amount.text).toDouble();
    if (existing == null) {
      await LocalDb.instance.addDebt(name.text.trim(), nominal);
    } else {
      await LocalDb.instance.updateDebt(existing['id'] as int, name.text.trim(), nominal);
    }
    changed();
  }
  name.dispose(); amount.dispose();
}
