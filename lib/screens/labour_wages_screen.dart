import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/fmt.dart';

/// Monthly wages for daily-wage labour from the labour attendance records.
class LabourWagesScreen extends StatefulWidget {
  const LabourWagesScreen({super.key});
  @override
  State<LabourWagesScreen> createState() => _LabourWagesScreenState();
}

class _LabourWagesScreenState extends State<LabourWagesScreen> {
  DateTime _m = DateTime(DateTime.now().year, DateTime.now().month);
  String get _key => '${_m.year}-${_m.month.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _load() async {
    final people = await Db.c('labour').get();
    final att = await Db.c('labourAttendance')
        .where('date', isGreaterThanOrEqualTo: '$_key-01')
        .where('date', isLessThanOrEqualTo: '$_key-31')
        .get();
    final rows = <Map<String, dynamic>>[];
    for (final p in people.docs) {
      final recs = att.docs.where((a) => a.data()['labour'] == p.id).map((a) => a.data()).toList();
      final full = recs.where((r) => r['status'] == 'Present').length;
      final half = recs.where((r) => r['status'] == 'Half-day').length;
      final ot = recs.fold<double>(0, (s, r) => s + n(r['overtimeHrs']));
      final wage = n(p.data()['dailyWage']);
      final days = full + 0.5 * half;
      final pay = r2(days * wage + ot * wage / 12);
      rows.add({'name': p.data()['name'], 'contractor': p.data()['contractor'] ?? '', 'days': days, 'ot': ot, 'wage': wage, 'pay': pay});
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _m = DateTime(_m.year, _m.month - 1)), icon: const Icon(Icons.chevron_left)),
        Text('Labour wages $_key', style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: () => setState(() => _m = DateTime(_m.year, _m.month + 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        future: _load(),
        builder: (context, s) {
          if (s.hasError) return Text('${s.error}');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = s.data!;
          if (rows.isEmpty) return const Text('Add labour in Masters first.');
          final total = rows.fold<double>(0, (t, r) => t + n(r['pay']));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in rows)
              Card(
                child: ListTile(
                  title: Text('${r['name']} - ${money(r['pay'])}'),
                  subtitle: Text('${r['contractor']}  |  ${r['days']} days x ${money(r['wage'])}  +  OT ${r['ot']}h'),
                ),
              ),
            Text('Total labour wages: ${money(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Wage = days (half-day = 0.5) x daily wage + overtime hours x daily wage / 12. Record the payment in Expenses (Labour).',
                style: TextStyle(fontSize: 11)),
          ]);
        },
      ),
    ]);
  }
}
