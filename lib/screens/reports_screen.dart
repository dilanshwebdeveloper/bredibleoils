import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/db.dart';
import '../core/export.dart';
import '../core/fmt.dart';
import 'tally_export.dart';

typedef Data = Map<String, List<Map<String, dynamic>>>;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late String _from, _to;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    _to = today();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => isFrom ? _from = _fmtDate(d) : _to = _fmtDate(d));
  }

  Future<Data> _load() async {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final c in ['purchases', 'docPurchases', 'productions', 'invoices', 'expenses', 'attendance']) {
      final s = await Db.c(c).where('date', isGreaterThanOrEqualTo: _from).where('date', isLessThanOrEqualTo: _to).get();
      out[c] = s.docs.map((d) => d.data()).where((e) => e['status'] != 'Voided').toList();
    }
    return out;
  }

  double _sum(List<Map<String, dynamic>> l, String k) => l.fold(0.0, (s, e) => s + n(e[k]));

  List<(String, String)> _summary(Data d) {
    final inv = d['invoices']!.where((e) => e['status'] != 'Cancelled').toList();
    final pur = d['purchases']!, pr = d['productions']!, ex = d['expenses']!;
    final seed = _sum(pr, 'seedKg'), oil = _sum(pr, 'oilKg'), kh = _sum(pr, 'khaliKg');
    final sales = _sum(inv, 'taxable');
    final purAmt = _sum(pur, 'amount') + _sum(d['docPurchases']!, 'amount');
    final exp = _sum(ex, 'amount');
    return [
      ('Seed purchased', '${kg(_sum(pur, 'netKg'))} KG'),
      ('Purchase amount (seed + DOC)', money(purAmt)),
      ('Seed crushed', '${kg(seed)} KG'),
      ('Oil produced', '${kg(oil)} KG'),
      ('Khali produced', '${kg(kh)} KG'),
      ('Oil yield', seed == 0 ? '-' : '${(oil / seed * 100).toStringAsFixed(2)} %'),
      ('Wastage', '${kg(_sum(pr, 'wastageKg'))} KG'),
      ('Invoices (not cancelled)', '${inv.length}'),
      ('Sales taxable value', money(sales)),
      ('GST charged', money(_sum(inv, 'cgst') + _sum(inv, 'sgst') + _sum(inv, 'igst'))),
      ('Sales total', money(_sum(inv, 'grandTotal'))),
      ('Expenses', money(exp)),
      ('Estimated profit (sales - purchases - expenses)', money(sales - purAmt - exp)),
    ];
  }

  Future<void> _pdf(Data d) async {
    final rows = _summary(d);
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (c) => [
        pw.Text('B.R. Edible Oils Pvt. Ltd. - Business report', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Period: $_from to $_to'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(data: [for (final r in rows) [r.$1, r.$2]], headerCount: 0),
        pw.SizedBox(height: 8),
        pw.Text('Profit is an estimate: it ignores opening/closing stock value and other accounting adjustments.',
            style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'report_${_from}_to_$_to.pdf');
  }

  Future<void> _tally() async {
    try {
      final xml = await buildTallyXml(_from, _to);
      if (!mounted) return;
      await saveOrShare(context, 'tally_vouchers_${_from}_to_$_to.xml', xml, mime: 'text/xml');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today, size: 16), label: Text('From $_from')),
        OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today, size: 16), label: Text('To $_to')),
        FilledButton(onPressed: () => setState(() => _tick++), child: const Text('Refresh')),
      ]),
      const SizedBox(height: 12),
      FutureBuilder<Data>(
        key: ValueKey('$_from$_to$_tick'),
        future: _load(),
        builder: (context, s) {
          if (s.hasError) return Text('${s.error}');
          if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
          final d = s.data!;
          final mach = <String, List<double>>{};
          for (final p in d['productions']!) {
            final m = mach.putIfAbsent('${p['machineName']}', () => [0, 0, 0, 0]);
            m[0] += n(p['seedKg']); m[1] += n(p['oilKg']); m[2] += n(p['khaliKg']); m[3] += 1;
          }
          final daily = <String, List<double>>{};
          for (final p in d['productions']!) {
            final m = daily.putIfAbsent('${p['date']}', () => [0, 0, 0]);
            m[0] += n(p['seedKg']); m[1] += n(p['oilKg']); m[2] += n(p['khaliKg']);
          }
          final att = <String, List<int>>{};
          for (final a in d['attendance']!) {
            final m = att.putIfAbsent('${a['employeeName']}', () => [0, 0, 0, 0]);
            switch ('${a['status']}') {
              case 'Present': m[0]++; break;
              case 'Half-day': m[1]++; break;
              case 'Leave': m[2]++; break;
              default: m[3]++;
            }
          }
          Widget section(String t, List<Widget> kids) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ...kids,
                  ]),
                ),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            section('Summary', [
              for (final r in _summary(d))
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(r.$1)), Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600))])),
              const Text('Profit is an estimate (stock value not included).', style: TextStyle(fontSize: 11)),
            ]),
            section('Machine efficiency', [
              if (mach.isEmpty) const Text('No production in this period'),
              for (final e in mach.entries)
                Text('${e.key}: ${e.value[3].toInt()} runs - seed ${kg(e.value[0])} -> oil ${kg(e.value[1])} KG '
                    '(${e.value[0] == 0 ? '-' : (e.value[1] / e.value[0] * 100).toStringAsFixed(1)}%) + khali ${kg(e.value[2])}'),
            ]),
            section('Daily production', [
              if (daily.isEmpty) const Text('No production in this period'),
              for (final k in (daily.keys.toList()..sort()))
                Text('$k: seed ${kg(daily[k]![0])}  oil ${kg(daily[k]![1])}  khali ${kg(daily[k]![2])} KG'),
            ]),
            section('Staff attendance', [
              if (att.isEmpty) const Text('No attendance in this period'),
              for (final e in att.entries)
                Text('${e.key}: present ${e.value[0]}, half-day ${e.value[1]}, leave ${e.value[2]}, absent ${e.value[3]}'),
            ]),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(onPressed: () => _pdf(d), icon: const Icon(Icons.picture_as_pdf), label: const Text('Report PDF')),
              OutlinedButton.icon(onPressed: _tally, icon: const Icon(Icons.upload_file), label: const Text('TallyPrime export (XML)')),
            ]),
            const SizedBox(height: 6),
            const Text('Tally: create ledgers named Sales, Purchase, CGST, SGST, IGST, Round Off and each customer/supplier '
                'with the same name as in this app, then Import in TallyPrime. Not yet tested against a live Tally.',
                style: TextStyle(fontSize: 11)),
          ]);
        },
      ),
    ]);
  }
}
