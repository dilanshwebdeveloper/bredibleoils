import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';

import '../core/db.dart';
import '../core/fmt.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime _m = DateTime(DateTime.now().year, DateTime.now().month);
  int _tick = 0;
  bool _busy = false;

  String get _key => '${_m.year}-${_m.month.toString().padLeft(2, '0')}';
  int get _days => DateTime(_m.year, _m.month + 1, 0).day;

  Future<List<Map<String, dynamic>>> _load() async {
    final saved = await Db.c('payroll').where('month', isEqualTo: _key).get();
    if (saved.docs.isNotEmpty) return saved.docs.map((d) => {...d.data(), '_final': true}).toList();
    final co = (await Db.c('settings').doc('company').get()).data() ?? {};
    double cfg(String k, double d) => co[k] is num ? n(co[k]) : d;
    final pfPct = cfg('pfPercent', 12), pfCap = cfg('pfWageCap', 15000), esiPct = cfg('esiPercent', 0.75), esiLimit = cfg('esiWageLimit', 21000);
    final emps = await Db.c('employees').get();
    final att = await Db.c('attendance')
        .where('date', isGreaterThanOrEqualTo: '$_key-01')
        .where('date', isLessThanOrEqualTo: '$_key-31')
        .get();
    final rows = <Map<String, dynamic>>[];
    for (final e in emps.docs) {
      final recs = att.docs.where((a) => a.data()['employee'] == e.id).map((a) => a.data()).toList();
      int cnt(String s) => recs.where((r) => r['status'] == s).length;
      final present = cnt('Present'), half = cnt('Half-day'), leave = cnt('Leave'), absent = cnt('Absent');
      final ot = recs.fold<double>(0, (s, r) => s + n(r['overtimeHrs']));
      final salary = n(e.data()['monthlySalary']);
      final perDay = salary / _days;
      final payDays = present + 0.5 * half + leave;
      final gross = r2(perDay * payDays);
      final otPay = r2(ot * perDay / 12);
      final pf = e.data()['pfApplicable'] == 'Yes' ? r2((gross < pfCap ? gross : pfCap) * pfPct / 100) : 0.0;
      final esi = (e.data()['esiApplicable'] == 'Yes' && gross + otPay <= esiLimit) ? r2((gross + otPay) * esiPct / 100) : 0.0;
      rows.add({
        'month': _key, 'employee': e.id, 'employeeName': e.data()['name'], 'monthlySalary': salary,
        'daysInMonth': _days, 'present': present, 'halfDays': half, 'leave': leave, 'absent': absent,
        'overtimeHrs': ot, 'basicPay': gross, 'overtimePay': otPay, 'pf': pf, 'esi': esi, 'netPay': r2(gross + otPay - pf - esi), '_final': false,
      });
    }
    return rows;
  }

  Future<void> _finalise(List<Map<String, dynamic>> rows) async {
    setState(() => _busy = true);
    try {
      final b = Db.fs.batch();
      for (final r in rows) {
        final data = Map<String, dynamic>.from(r)..remove('_final');
        b.set(Db.c('payroll').doc('${_key}_${r['employee']}'), {...data, 'createdAt': FieldValue.serverTimestamp(), 'by': Db.email});
      }
      Db.audit(b, 'payroll', 'Payroll finalised for $_key (${rows.length} employees)');
      await b.commit();
      setState(() => _tick++);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not finalise: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlock(List<Map<String, dynamic>> rows) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unlock this month?'),
        content: const Text('The saved payroll for this month is deleted so it can be calculated again. A note is kept in the Audit trail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Unlock')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      for (var i = 0; i < rows.length; i += 10) {
        final b = Db.fs.batch();
        for (final r in rows.skip(i).take(10)) {
          b.delete(Db.c('payroll').doc('${_key}_${r['employee']}'));
        }
        await b.commit();
      }
      final a = Db.fs.batch();
      Db.audit(a, 'delete', 'Payroll $_key unlocked (${rows.length} rows deleted)');
      await a.commit();
      setState(() => _tick++);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _m = DateTime(_m.year, _m.month - 1)), icon: const Icon(Icons.chevron_left)),
        Text('Payroll $_key', style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: () => setState(() => _m = DateTime(_m.year, _m.month + 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey('$_key$_tick'),
        future: _load(),
        builder: (context, s) {
          if (s.hasError) return Text('${s.error}');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = s.data!;
          if (rows.isEmpty) return const Text('Add employees in Masters first.');
          final isFinal = rows.first['_final'] == true;
          final total = rows.fold<double>(0, (t, r) => t + n(r['netPay']));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isFinal ? 'FINALISED - cannot be changed' : 'Draft - not saved yet', style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final r in rows)
              Card(
                child: ListTile(
                  title: Text('${r['employeeName']} - ${money(r['netPay'])}'),
                  subtitle: Text('Salary ${money(r['monthlySalary'])} | present ${r['present']}, half ${r['halfDays']}, leave ${r['leave']}, absent ${r['absent']} | OT ${r['overtimeHrs']}h = ${money(r['overtimePay'])} | PF ${money(r['pf'])} ESI ${money(r['esi'])}'),
                ),
              ),
            Text('Total payable: ${money(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (!isFinal)
              FilledButton.icon(
                onPressed: _busy ? null : () => _finalise(rows),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Finalise this month'),
              ),
            if (isFinal && context.read<AppState>().isAdmin)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _unlock(rows),
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock this month (admin)'),
              ),
            const SizedBox(height: 8),
            const Text('Method: salary / days in month x (present + half-day x 0.5 + paid leave). Overtime per hour = daily pay / 12. '
                'PF / ESI use the percentages in Company Settings and the PF/ESI flags on each employee. TDS is not calculated. Confirm all rules with your CA.', style: TextStyle(fontSize: 11)),
          ]);
        },
      ),
    ]);
  }
}
