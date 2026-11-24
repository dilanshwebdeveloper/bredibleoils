import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../widgets/crud_screen.dart';
import 'audit_screen.dart';
import 'import_screen.dart';
import 'labour_wages_screen.dart';
import 'shipments_screen.dart';
import 'backup_screen.dart';
import 'payroll_screen.dart';
import 'reports_screen.dart';
import 'dashboard_screen.dart';
import 'inventory_screen.dart';
import 'masters_screen.dart';
import 'modules.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';
import 'tanks_screen.dart';

class _Mod {
  final String id, label;
  final IconData icon;
  final Widget Function(AppState) build;
  const _Mod(this.id, this.label, this.icon, this.build);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _sel = 'dashboard';

  @override
  void initState() {
    super.initState();
  }

  List<_Mod> _mods(AppState a) => [
        _Mod('dashboard', 'Dashboard', Icons.dashboard_outlined, (a) => const DashboardScreen()),
        _Mod('purchase', 'Purchase', Icons.shopping_cart_outlined, purchaseModule),
        _Mod('production', 'Production', Icons.precision_manufacturing_outlined, productionModule),
        _Mod('inventory', 'Inventory & Khali', Icons.warehouse_outlined, (a) => const InventoryScreen()),
        _Mod('tanks', 'Oil Tanks', Icons.oil_barrel_outlined, (a) => const TanksScreen()),
        _Mod('quality', 'Quality Control', Icons.science_outlined, qualityModule),
        _Mod('sales', 'Sales & GST Billing', Icons.receipt_long_outlined, (a) => SalesScreen(app: a)),
        _Mod('shipments', 'Shipments & Tracking', Icons.local_shipping_outlined, (a) => ShipmentsScreen(app: a)),
        _Mod('attendance', 'Staff Attendance', Icons.badge_outlined, attendanceModule),
        _Mod('expenses', 'Expenses', Icons.payments_outlined, expensesModule),
        _Mod('reports', 'Reports & Tally', Icons.bar_chart, (a) => const ReportsScreen()),
        _Mod('payroll', 'Payroll', Icons.account_balance_wallet_outlined, (a) => const TabsScreen({'Staff payroll': PayrollScreen(), 'Labour wages': LabourWagesScreen()})),
        _Mod('masters', 'Masters', Icons.folder_open_outlined, (a) => MastersScreen(app: a)),
        _Mod('audit', 'Audit Trail', Icons.history, (a) => const AuditScreen()),
        _Mod('users', 'Users & Roles', Icons.admin_panel_settings_outlined, usersModule),
        _Mod('import', 'Import & Opening Stock', Icons.upload_file_outlined, (a) => const ImportScreen()),
        _Mod('backup', 'Backup', Icons.cloud_download_outlined, (a) => const BackupScreen()),
        _Mod('settings', 'Company Settings', Icons.settings_outlined, (a) => const SettingsScreen()),
      ].where((m) => a.can(m.id)).toList();

  Widget _menu(AppState a, List<_Mod> mods, {bool closeDrawer = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Image.asset('assets/logo.jpg', height: 90),
        ),
        Text(a.profile?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(a.role.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              for (final m in mods)
                ListTile(
                  dense: true,
                  leading: Icon(m.icon),
                  title: Text(m.label),
                  selected: m.id == _sel,
                  onTap: () {
                    setState(() => _sel = m.id);
                    if (closeDrawer) Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
        ListTile(dense: true, leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: a.signOut),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    final mods = _mods(a);
    final cur = mods.firstWhere((m) => m.id == _sel, orElse: () => mods.first);
    final wide = MediaQuery.of(context).size.width >= 900;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(key: ValueKey(cur.id), child: cur.build(a)),
    );
    final bar = AppBar(
      title: Text(cur.label),
      actions: [
        IconButton(
          tooltip: 'Light / dark theme',
          icon: Icon(a.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: a.toggleTheme,
        ),
      ],
    );
    if (wide) {
      return Scaffold(
        appBar: bar,
        body: Row(children: [
          SizedBox(width: 260, child: _menu(a, mods)),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(appBar: bar, drawer: Drawer(child: SafeArea(child: _menu(a, mods, closeDrawer: true))), body: body);
  }
}
