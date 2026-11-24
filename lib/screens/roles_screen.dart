import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/db.dart';

const _labels = {
  'dashboard': 'Dashboard', 'purchase': 'Purchase', 'production': 'Production', 'inventory': 'Inventory & Khali',
  'tanks': 'Oil tanks', 'quality': 'Quality control', 'sales': 'Sales & GST billing', 'shipments': 'Shipments & tracking',
  'attendance': 'Attendance', 'expenses': 'Expenses', 'masters': 'Masters', 'audit': 'Audit trail',
  'reports': 'Reports & Tally', 'payroll': 'Payroll & labour wages',
};

/// Admin chooses which screens each role can open. (Firestore security rules still limit what each role may do.)
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  static const _editable = ['manager', 'accountant', 'operator'];
  late final Map<String, Set<String>> _sel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = context.read<AppState>();
    _sel = {for (final r in _editable) r: {...(a.perms[r] ?? roleModules[r]!)}};
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final b = Db.fs.batch();
    b.set(Db.c('settings').doc('permissions'), {for (final r in _editable) r: _sel[r]!.toList()});
    Db.audit(b, 'update', 'Role permissions changed');
    await Db.commit(b);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Role permissions')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Admin always sees everything. "Employee" (attendance entry only) and "Driver" (own shipments only) are fixed for safety.'),
        ),
        for (final r in _editable)
          Card(
            child: ExpansionTile(
              title: Text(r.toUpperCase()),
              subtitle: Text('${_sel[r]!.length} screens'),
              children: [
                for (final m in configurable)
                  CheckboxListTile(
                    dense: true,
                    title: Text(_labels[m] ?? m),
                    value: _sel[r]!.contains(m),
                    onChanged: (v) => setState(() => v == true ? _sel[r]!.add(m) : _sel[r]!.remove(m)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save), label: const Text('Save permissions')),
      ]),
    );
  }
}
