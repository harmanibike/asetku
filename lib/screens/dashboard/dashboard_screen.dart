import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Nilai berikut hanya data contoh untuk rancangan antarmuka.
    const totalAssets = 125750000.0;
    const invested = 111450000.0;
    const profit = 14300000.0;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ASETKU', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            Text('Personal Wealth Tracker', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.navy, Color(0xFF263F60)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL KEKAYAAN', style: TextStyle(color: Color(0xFFCAD4E1), fontSize: 11, letterSpacing: 1.1)),
                  const SizedBox(height: 9),
                  Text(formatRupiah(totalAssets), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFF70D6A5), size: 18),
                      const SizedBox(width: 5),
                      Text('+${formatRupiah(profit)}', style: const TextStyle(color: Color(0xFF70D6A5), fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      const Text('keuntungan berjalan*', style: TextStyle(color: Color(0xFFCAD4E1), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('*Ilustrasi tampilan, bukan data investasi nyata.', style: TextStyle(color: Color(0xFFCAD4E1), fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _summaryCard('Total Modal', formatRupiah(invested), Icons.account_balance_wallet_outlined)),
                const SizedBox(width: 12),
                Expanded(child: _summaryCard('Untung / Rugi', formatRupiah(profit), Icons.show_chart_rounded, positive: true)),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Portofolio Saya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                TextButton(onPressed: () {}, child: const Text('Lihat semua')),
              ],
            ),
            const SizedBox(height: 6),
            _assetRow(Icons.show_chart, 'Saham', 'Saham Indonesia & US', 'Rp 45.000.000', const Color(0xFF477FC2)),
            _assetRow(Icons.account_balance, 'Reksadana & ETF', 'Berbagai produk', 'Rp 28.500.000', const Color(0xFF39A78A)),
            _assetRow(Icons.circle_outlined, 'Emas', 'Fisik & digital', 'Rp 20.000.000', const Color(0xFFC9A45C)),
            _assetRow(Icons.currency_bitcoin, 'Crypto', 'Aset digital', 'Rp 12.000.000', const Color(0xFF8874C8)),
            _assetRow(Icons.savings_outlined, 'Kas & Deposito', 'Bank, e-wallet, deposito', 'Rp 20.250.000', const Color(0xFFDA8A69)),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Tambah Aset', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Aset'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Transaksi'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Analisis'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, {bool positive = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: positive ? const Color(0xFF269B70) : AppTheme.gold),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.navy)),
        ]),
      ),
    );
  }

  Widget _assetRow(IconData icon, String title, String subtitle, String value, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.13), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}
