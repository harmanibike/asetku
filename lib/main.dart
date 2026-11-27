import 'package:flutter/material.dart';
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
    _db = await openDatabase(p.join(dir, 'asetku.db'), version: 2, onCreate: (db, version) async {
      await db.execute('CREATE TABLE assets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, cost REAL NOT NULL, value REAL NOT NULL, created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE debts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, amount REAL NOT NULL, created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, assets REAL NOT NULL, debts REAL NOT NULL, net_worth REAL NOT NULL, recorded_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE asset_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL, type TEXT NOT NULL, units REAL NOT NULL, unit_price REAL NOT NULL, fee REAL NOT NULL DEFAULT 0, transaction_date TEXT NOT NULL, note TEXT NOT NULL, created_at TEXT NOT NULL)');
    }, onUpgrade: (db, oldVersion, newVersion) async { if (oldVersion < 2) await db.execute('CREATE TABLE asset_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL, type TEXT NOT NULL, units REAL NOT NULL, unit_price REAL NOT NULL, fee REAL NOT NULL DEFAULT 0, transaction_date TEXT NOT NULL, note TEXT NOT NULL, created_at TEXT NOT NULL)'); });
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
    await d.insert('asset_transactions', {'asset_id': assetId, 'type': tx.type, 'units': tx.units, 'unit_price': tx.unitPrice, 'fee': tx.fee, 'transaction_date': (tx.date ?? DateTime.now()).toIso8601String(), 'note': note, 'created_at': DateTime.now().toIso8601String()});
    final position = await positionForAsset(assetId);
    await d.update('assets', {'cost': position.costBasis}, where: 'id = ?', whereArgs: [assetId]);
  }
  Future<List<Map<String, Object?>>> transactionsForAsset(int assetId) async => (await db).query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date DESC, id DESC');
  Future<PortfolioPosition> positionForAsset(int assetId) async {
    final rows = await (await db).query('asset_transactions', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'transaction_date ASC, id ASC');
    return calculatePosition(rows.map((r) => PortfolioTransaction(type: r['type'] as String, units: (r['units'] as num).toDouble(), unitPrice: (r['unit_price'] as num).toDouble(), fee: (r['fee'] as num).toDouble(), date: DateTime.parse(r['transaction_date'] as String))));
  }
  Future<void> delete(String table, int id) async {
    final d = await db;
    if (table == 'assets') { await d.delete('asset_transactions', where: 'asset_id = ?', whereArgs: [id]); await d.delete('assets', where: 'id = ?', whereArgs: [id]); }
    if (table == 'debts') await d.delete('debts', where: 'id = ?', whereArgs: [id]);
  }
  Future<Map<String, double>> totals() async {
    final d = await db;
    final a = await d.rawQuery('SELECT COALESCE(SUM(value),0) total, COALESCE(SUM(cost),0) cost FROM assets');
    final b = await d.rawQuery('SELECT COALESCE(SUM(amount),0) total FROM debts');
    final assets = (a.first['total'] as num).toDouble();
    final cost = (a.first['cost'] as num).toDouble();
    final debts = (b.first['total'] as num).toDouble();
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
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.account_balance_wallet, color: Color(0xFF1769AA)), SizedBox(width: 9), Text('Asetku', style: TextStyle(fontWeight: FontWeight.w800))])),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Ringkasan'),
        NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Aset'),
        NavigationDestination(icon: Icon(Icons.credit_card_outlined), label: 'Utang'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Pengaturan'),
      ]),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.changed});
  final VoidCallback changed;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, double>>(
    future: LocalDb.instance.totals(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final t = snapshot.data!;
      final assets = t['assets']!;
      final debts = t['debts']!;
      final net = t['net']!;
      final pnl = t['pnl']!;
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
      body: FutureBuilder<List<Object>>(key: ValueKey(revision), future: Future.wait<Object>([LocalDb.instance.positionForAsset(id), LocalDb.instance.transactionsForAsset(id)]), builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final p = s.data![0] as PortfolioPosition; final rows = s.data![1] as List<Map<String, Object?>>;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Posisi investasi', style: TextStyle(fontWeight: FontWeight.w800)),
            positionLine('Jumlah unit', p.units.toStringAsFixed(6)), positionLine('Harga rata-rata', rupiah(p.averageCost)), positionLine('Modal tersisa', rupiah(p.costBasis)), positionLine('Laba/rugi terealisasi', rupiah(p.realizedProfitLoss)),
          ]))),
          const SizedBox(height: 12), const Text('Riwayat transaksi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (rows.isEmpty) const Text('Belum ada transaksi beli atau jual.'),
          ...rows.map((r) { final buy = r['type'] == 'buy'; return Card(child: ListTile(leading: Icon(buy ? Icons.south_west : Icons.north_east, color: buy ? Colors.green : Colors.red), title: Text((buy ? 'Beli ' : 'Jual ') + r['units'].toString()), subtitle: Text(DateFormat('dd MMM yyyy').format(DateTime.parse(r['transaction_date'] as String)) + ' • ' + (r['note'] as String)), trailing: Text(rupiah((r['units'] as num) * (r['unit_price'] as num))))); }),
          const SizedBox(height: 80),
        ]);
      }));
  }
}
Widget positionLine(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w700))]));
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
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
    Text('Pengaturan', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
    SizedBox(height: 12),
    Card(child: ListTile(leading: Icon(Icons.storage_outlined), title: Text('Database lokal'), subtitle: Text('Data tersimpan di perangkat menggunakan SQLite.'))),
    Card(child: ListTile(leading: Icon(Icons.backup_outlined), title: Text('Backup & pemulihan'), subtitle: Text('Disiapkan pada tahap berikutnya.'))),
    Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('Mode offline'), subtitle: Text('Pencatatan tetap berjalan tanpa internet.'))),
    Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Tentang Asetku'), subtitle: Text('Gratis • Tanpa akun • Tanpa lisensi'))),
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
