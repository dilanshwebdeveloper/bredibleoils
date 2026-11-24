import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/form_page.dart';

/// Simple CSV reader (handles quotes, commas inside quotes, Windows line ends, BOM).
List<List<String>> parseCsv(String text) {
  if (text.startsWith('\ufeff')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (q) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == ',') {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

const _kinds = <String, String>{
  'Suppliers': 'name,phone,gstin,address',
  'Customers': 'name,gstin,state,address,phone,email',
  'Employees': 'name,code,designation,phone,shift,monthlySalary',
  'Labour': 'name,code,contractor,phone,shift,dailyWage',
  'Old expenses': 'date,category,amount,paidTo,mode,note',
  'Old supplier payments': 'date,supplier,amount,mode,reference',
};

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String _kind = 'Suppliers';
  String _status = '';
  bool _busy = false;

  // ---------------------------------------------------------- opening stock
  Future<void> _saveOpening(Map<String, dynamic> v) async {
    final q = n(v['kg']);
    if (q <= 0) throw Exception('Quantity must be more than 0');
    final kind = '${v['kind']}';
    final b = Db.fs.batch();
    if (kind == 'Mustard oil') {
      if (v['tank'] == null) throw Exception('Select the tank');
      final tank = (v['_tank'] as Map<String, dynamic>?) ?? {};
      final comp = (await Db.c('settings').doc('company').get()).data() ?? {};
      final dens = n(comp['oilDensity']) > 0 ? n(comp['oilDensity']) : 0.915;
      if ((n(tank['oilKg']) + q) / dens > n(tank['capacityL'])) throw Exception('Tank capacity would be exceeded');
      Db.tankMove(b, tankId: '${v['tank']}', qty: q, type: 'opening', refType: 'opening', note: '${v['note'] ?? 'Opening stock'}');
    } else {
      if (v['godown'] == null) throw Exception('Select the godown');
      final g = (v['_godown'] as Map<String, dynamic>?) ?? {};
      final item = kind == 'Mustard seed' ? 'seed' : kind == 'Khali' ? 'khali' : 'doc';
      if (item != 'doc' && g['type'] != item) {
        throw Exception(item == 'seed' ? 'Seed must go into a seed godown' : 'Khali must go into the Khali godown');
      }
      Db.stockMove(b, godownId: '${v['godown']}', item: item, qty: q, type: 'opening', refType: 'opening', note: '${v['note'] ?? 'Opening stock'}');
    }
    Db.audit(b, 'opening-stock', '$kind ${kg(q)} KG as on ${v['date']}');
    await Db.commit(b);
  }

  // ----------------------------------------------------------------- CSV import
  Future<void> _pickAndImport() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final table = parseCsv(_utf8(bytes));
    if (table.length < 2) {
      setState(() => _status = 'The file has no data rows. First row must be the column names.');
      return;
    }
    final head = table.first.map((e) => e.toLowerCase()).toList();
    final recs = <Map<String, String>>[];
    for (final row in table.skip(1)) {
      recs.add({for (var i = 0; i < head.length && i < row.length; i++) head[i]: row[i]});
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Import ${recs.length} rows into "$_kind"?'),
        content: Text('Columns found: ${head.join(', ')}\n\nExisting records are not changed; new ones are added.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _status = 'Importing...'; });
    try {
      _status = await _import(recs);
    } catch (e) {
      _status = 'Import stopped: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  String _utf8(List<int> b) {
    try {
      return const Utf8Decoder().convert(b);
    } catch (_) {
      return String.fromCharCodes(b);
    }
  }

  Future<String> _import(List<Map<String, String>> recs) async {
    var b = Db.fs.batch();
    var ops = 0, okRows = 0;
    final errs = <String>[];
    Future<void> flush() async {
      if (ops > 0) await b.commit();
      b = Db.fs.batch();
      ops = 0;
    }

    void add(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> d) {
      b.set(ref, d);
      ops++;
    }

    final stamp = {'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email, 'imported': true};
    Map<String, String> sup = {};
    if (_kind == 'Old supplier payments') {
      final s = await Db.c('suppliers').get();
      sup = {for (final d in s.docs) '${d.data()['name']}'.toLowerCase(): d.id};
    }
    for (var i = 0; i < recs.length; i++) {
      final r = recs[i];
      final line = i + 2;
      if (ops > 14) await flush();
      String g(String k) => r[k] ?? '';
      try {
        switch (_kind) {
          case 'Suppliers':
            if (g('name').isEmpty) throw 'name missing';
            add(Db.c('suppliers').doc(), {'name': g('name'), 'phone': g('phone'), 'gstin': g('gstin'), 'address': g('address'), ...stamp});
            break;
          case 'Customers':
            if (g('name').isEmpty) throw 'name missing';
            final s = g('state').toLowerCase();
            final st = indianStates.where((x) => s.isNotEmpty && (x.toLowerCase() == s || x.substring(0, 2) == s.padLeft(2, '0') || x.toLowerCase().contains(s))).toList();
            if (st.isEmpty) throw 'state "${g('state')}" not recognised (use e.g. "08 - Rajasthan")';
            add(Db.c('customers').doc(), {'name': g('name'), 'gstin': g('gstin'), 'state': st.first, 'address': g('address'), 'phone': g('phone'), 'email': g('email'), ...stamp});
            break;
          case 'Employees':
            if (g('name').isEmpty) throw 'name missing';
            final ref = Db.c('employees').doc();
            add(ref, {'name': g('name'), 'code': g('code'), 'designation': g('designation'), 'phone': g('phone'),
              'shift': g('shift').isEmpty ? 'General' : g('shift'), 'monthlySalary': n(g('monthlysalary')),
              'pfApplicable': 'No', 'esiApplicable': 'No', ...stamp});
            add(Db.c('attendanceRoster').doc(ref.id), {'name': g('name'), 'code': g('code'), 'type': 'staff'});
            break;
          case 'Labour':
            if (g('name').isEmpty) throw 'name missing';
            final ref = Db.c('labour').doc();
            add(ref, {'name': g('name'), 'code': g('code'), 'contractor': g('contractor'), 'phone': g('phone'),
              'shift': g('shift').isEmpty ? 'General' : g('shift'), 'dailyWage': n(g('dailywage')), ...stamp});
            add(Db.c('attendanceRoster').doc(ref.id), {'name': g('name'), 'code': g('code'), 'type': 'labour'});
            break;
          case 'Old expenses':
            if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(g('date'))) throw 'date must be yyyy-mm-dd';
            if (n(g('amount')) <= 0) throw 'amount missing';
            add(Db.c('expenses').doc(), {'date': g('date'), 'category': g('category').isEmpty ? 'Other' : g('category'), 'amount': n(g('amount')),
              'paidTo': g('paidto'), 'mode': g('mode'), 'note': g('note'), ...stamp});
            break;
          case 'Old supplier payments':
            if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(g('date'))) throw 'date must be yyyy-mm-dd';
            final id = sup[g('supplier').toLowerCase()];
            if (id == null) throw 'supplier "${g('supplier')}" not found - import suppliers first';
            add(Db.c('supplierPayments').doc(), {'date': g('date'), 'supplier': id, 'supplierName': g('supplier'), 'amount': n(g('amount')),
              'mode': g('mode'), 'reference': g('reference'), ...stamp});
            break;
        }
        okRows++;
      } catch (e) {
        errs.add('Row $line: $e');
      }
    }
    final a = Db.fs.batch();
    Db.audit(a, 'import', '$_kind: $okRows rows imported');
    await flush();
    await a.commit();
    return 'Imported $okRows of ${recs.length} rows.${errs.isEmpty ? '' : '\nSkipped:\n${errs.take(15).join('\n')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final header = _kinds[_kind]!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('1. Opening stock (stock you already have today)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Enter the stock lying in each godown / tank on the day you start using the app. Do this once per godown / tank.'),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Add opening stock'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FormPage(
                    title: 'Opening stock',
                    fields: const [
                      FieldDef('date', 'As on date', FT.date),
                      FieldDef('kind', 'Stock type', FT.choice, options: ['Mustard seed', 'Khali', 'DOC', 'Mustard oil']),
                      FieldDef('godown', 'Godown (for seed / Khali / DOC)', FT.doc, coll: 'godowns', required: false),
                      FieldDef('tank', 'Tank (for Mustard oil)', FT.doc, coll: 'tanks', required: false),
                      FieldDef('kg', 'Quantity (KG)', FT.number),
                      FieldDef('note', 'Note', FT.text, required: false, initial: 'Opening stock'),
                    ],
                    onSave: _saveOpening,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('2. Import old records from a CSV file', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Make the list in Excel, save as CSV (comma separated), and import. The first row must have the column names shown below.'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'What do you want to import?'),
              items: _kinds.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 10),
            const Text('First row (column names):', style: TextStyle(fontSize: 12)),
            SelectableText(header, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy column names'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: header));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose CSV file & import'),
                onPressed: _busy ? null : _pickAndImport,
              ),
            ]),
            if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(_status)),
            const SizedBox(height: 8),
            const Text('Customers: state like "08 - Rajasthan" or just 08. Dates: 2026-04-15. Import Suppliers before Old supplier payments.',
                style: TextStyle(fontSize: 11)),
          ]),
        ),
      ),
      const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Old purchases, production and invoices'),
          subtitle: Text('These change stock and GST numbering, so they are not bulk-imported. Put today\'s stock in as Opening stock, '
              'and keep old invoices in your old records / Tally. Totals for past months can be added as Old expenses / payments.'),
        ),
      ),
    ]);
  }
}
