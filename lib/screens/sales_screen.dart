import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/form_page.dart';
import 'invoice_pdf.dart';

class SalesScreen extends StatelessWidget {
  final AppState app;
  const SalesScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: app.isBiz
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New invoice'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceForm())),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.c('invoices').orderBy('createdAt', descending: true).limit(300).snapshots(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.docs.isEmpty) return const Center(child: Text('No invoices yet'));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            for (final d in s.data!.docs)
              Card(
                child: ListTile(
                  title: Text('${d['invoiceNo']} - ${d['customerName']}'),
                  subtitle: Text('${d['date']} - ${money(d['grandTotal'])} - ${d['status']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => InvoiceDetail(id: d.id, app: app))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ Detail
class InvoiceDetail extends StatelessWidget {
  final String id;
  final AppState app;
  const InvoiceDetail({super.key, required this.id, required this.app});

  Future<Uint8List> _pdf(Map<String, dynamic> inv) async {
    final co = (await Db.c('settings').doc('company').get()).data() ?? {};
    return buildInvoicePdf(inv, co);
  }

  Future<void> _setStatus(BuildContext context, String status) async {
    final b = Db.fs.batch();
    b.update(Db.c('invoices').doc(id), {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == 'Delivered') 'deliveredAt': FieldValue.serverTimestamp(),
    });
    Db.audit(b, 'invoice-status', '$id -> $status', refId: id);
    await Db.commit(b);
  }

  Future<void> _cancel(BuildContext context, Map<String, dynamic> inv) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel invoice?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The invoice stays on record as Cancelled and its stock is returned.'),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel invoice')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    try {
      await Db.fs.runTransaction((tx) async {
        final ref = Db.c('invoices').doc(id);
        final cur = await tx.get(ref);
        if (cur.data()?['status'] == 'Cancelled') throw Exception('Already cancelled');
        tx.update(ref, {'status': 'Cancelled', 'cancelReason': reason.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
        for (final l in (inv['lines'] as List)) {
          final m = Map<String, dynamic>.from(l as Map);
          if (m['sourceType'] == 'tank') {
            Db.tankMove(tx, tankId: '${m['sourceId']}', qty: n(m['kg']), type: 'cancel-reversal', refType: 'invoice', refId: id, note: '${inv['invoiceNo']}');
          } else {
            Db.stockMove(tx, godownId: '${m['sourceId']}', item: m['product'] == 'Mustard Khali' ? 'khali' : 'doc',
                qty: n(m['kg']), type: 'cancel-reversal', refType: 'invoice', refId: id, note: '${inv['invoiceNo']}');
          }
        }
        Db.audit(tx, 'invoice-cancel', '${inv['invoiceNo']}: ${reason.text.trim()}', refId: id);
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _purge(BuildContext context, Map<String, dynamic> inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this cancelled invoice?'),
        content: const Text('It is removed for good (its invoice number stays unused). A copy of its details is kept in the Audit trail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final b = Db.fs.batch();
    b.delete(Db.c('invoices').doc(id));
    Db.audit(b, 'delete', 'invoice ${inv['invoiceNo']} ${inv['customerName']} ${money(inv['grandTotal'])} (was cancelled)', refId: id);
    await Db.commit(b);
    if (context.mounted) Navigator.pop(context);
  }

  void _irn(BuildContext context, Map<String, dynamic> inv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          title: 'IRN / e-way bill (typed manually)',
          initial: inv,
          fields: const [
            FieldDef('irn', 'IRN (from the GST e-invoice portal)', FT.text, required: false),
            FieldDef('irnDate', 'IRN date', FT.text, required: false),
            FieldDef('ewayBillNo', 'E-way bill no.', FT.text, required: false),
            FieldDef('ewayValidUpto', 'E-way bill valid up to', FT.text, required: false),
          ],
          onSave: (v) async {
            final b = Db.fs.batch();
            b.update(Db.c('invoices').doc(id), {
              'irn': v['irn'], 'irnDate': v['irnDate'], 'ewayBillNo': v['ewayBillNo'],
              'ewayValidUpto': v['ewayValidUpto'], 'updatedAt': FieldValue.serverTimestamp(),
            });
            Db.audit(b, 'invoice-irn', '${inv['invoiceNo']} IRN / e-way bill recorded manually', refId: id);
            await Db.commit(b);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Db.c('invoices').doc(id).snapshots(),
        builder: (context, s) {
          final inv = s.data?.data();
          if (inv == null) return const Center(child: CircularProgressIndicator());
          final fname = '${inv['invoiceNo']}'.replaceAll('/', '_');
          final cancelled = inv['status'] == 'Cancelled';
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${inv['invoiceNo']}', style: Theme.of(context).textTheme.headlineSmall),
            Text('${inv['customerName']} - ${inv['customerState'] ?? ''}'),
            Text('${inv['date']} - Status: ${inv['status']}${cancelled ? ' (${inv['cancelReason']})' : ''}'),
            const Divider(),
            for (final l in (inv['lines'] as List))
              ListTile(
                dense: true,
                title: Text('${l['product']} - ${kg(l['kg'])} KG @ ${l['rate']}'),
                subtitle: Text('HSN ${l['hsn']}  GST ${l['gst']}%  Taxable ${money(l['taxable'])}'),
              ),
            const Divider(),
            Text(inv['interstate'] == true
                ? 'IGST ${money(inv['igst'])}'
                : 'CGST ${money(inv['cgst'])}   SGST ${money(inv['sgst'])}'),
            Text('Grand total ${money(inv['grandTotal'])}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Vehicle ${inv['vehicleNo'] ?? '-'} | Transporter ${inv['transporter'] ?? '-'} | LR ${inv['lrNo'] ?? '-'} | Slip ${inv['slipNo'] ?? '-'}'),
            if ('${inv['irn'] ?? ''}'.isNotEmpty) Text('IRN: ${inv['irn']} (entered manually)'),
            if ('${inv['ewayBillNo'] ?? ''}'.isNotEmpty) Text('E-way bill: ${inv['ewayBillNo']} valid up to ${inv['ewayValidUpto'] ?? '-'}'),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share PDF (WhatsApp / email)'),
                onPressed: () async => Printing.sharePdf(bytes: await _pdf(inv), filename: '$fname.pdf'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text('Print / Save PDF'),
                onPressed: () => Printing.layoutPdf(name: fname, onLayout: (_) => _pdf(inv)),
              ),
              if (!cancelled && app.isBiz && inv['status'] == 'Created')
                OutlinedButton(onPressed: () => _setStatus(context, 'Dispatched'), child: const Text('Mark dispatched')),
              if (!cancelled && app.isBiz && inv['status'] == 'Dispatched')
                OutlinedButton(onPressed: () => _setStatus(context, 'Delivered'), child: const Text('Mark delivered')),
              if (!cancelled && app.isBiz)
                OutlinedButton(onPressed: () => _irn(context, inv), child: const Text('Record IRN / e-way bill')),
              if (!cancelled && app.isMgr)
                TextButton(onPressed: () => _cancel(context, inv), child: const Text('Cancel invoice')),
              if (cancelled && app.isAdmin)
                TextButton(onPressed: () => _purge(context, inv), child: const Text('Delete cancelled invoice')),
            ]),
          ]);
        },
      ),
    );
  }
}

// -------------------------------------------------------------------- Form
class InvoiceForm extends StatefulWidget {
  const InvoiceForm({super.key});
  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  final List<Map<String, dynamic>> _lines = [];
  final _vehicle = TextEditingController(), _transporter = TextEditingController(), _lr = TextEditingController(),
      _slip = TextEditingController(), _gross = TextEditingController(), _tare = TextEditingController();
  String? _custId;
  Map<String, dynamic> _cust = {};
  String _date = today();
  bool _busy = false;

  void _addLine() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          title: 'Add item',
          fields: const [
            FieldDef('product', 'Product', FT.choice, options: ['Mustard Oil', 'Mustard Khali', 'DOC']),
            FieldDef('tank', 'Oil taken from tank (for Mustard Oil)', FT.doc, coll: 'tanks', required: false),
            FieldDef('godown', 'Taken from godown (for Khali / DOC)', FT.doc, coll: 'godowns', required: false),
            FieldDef('kg', 'Quantity (KG)', FT.number),
            FieldDef('rate', 'Rate per KG (excl. GST)', FT.number),
            FieldDef('hsn', 'HSN code (blank = default)', FT.text, required: false),
            FieldDef('gst', 'GST rate %', FT.number, initial: 5),
          ],
          onSave: (v) async {
            final oil = v['product'] == 'Mustard Oil';
            if (n(v['kg']) <= 0 || n(v['rate']) <= 0) throw Exception('Quantity and rate must be more than 0');
            if (oil && v['tank'] == null) throw Exception('Select the tank the oil is taken from');
            if (!oil && v['godown'] == null) throw Exception('Select the godown');
            final hsn = '${v['hsn']}'.isEmpty ? (oil ? '1514' : '2306') : '${v['hsn']}';
            setState(() => _lines.add({
                  'product': v['product'],
                  'sourceType': oil ? 'tank' : 'godown',
                  'sourceId': oil ? v['tank'] : v['godown'],
                  'sourceName': oil ? v['tankName'] : v['godownName'],
                  'kg': n(v['kg']),
                  'rate': n(v['rate']),
                  'hsn': hsn,
                  'gst': n(v['gst']),
                }));
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_custId == null) return _msg('Select a customer');
    if (_lines.isEmpty) return _msg('Add at least one item');
    setState(() => _busy = true);
    try {
      final fyr = fy(DateTime.tryParse(_date));
      await Db.fs.runTransaction((tx) async {
        final cRef = Db.c('counters').doc('invoice_$fyr');
        final cSnap = await tx.get(cRef);
        final coSnap = await tx.get(Db.c('settings').doc('company'));
        final co = coSnap.data() ?? {};
        // check stock first (all reads before writes)
        final need = <String, double>{};
        for (final l in _lines) {
          final key = l['sourceType'] == 'tank'
              ? 'tank:${l['sourceId']}'
              : 'stock:${l['sourceId']}__${l['product'] == 'Mustard Khali' ? 'khali' : 'doc'}';
          need[key] = (need[key] ?? 0) + n(l['kg']);
        }
        for (final e in need.entries) {
          final isTank = e.key.startsWith('tank:');
          final ref = isTank ? Db.c('tanks').doc(e.key.substring(5)) : Db.c('stock').doc(e.key.substring(6));
          final snap = await tx.get(ref);
          final have = n(snap.data()?[isTank ? 'oilKg' : 'qtyKg']);
          if (have < e.value) throw Exception('Not enough stock for ${isTank ? 'tank ' : ''}${ref.id}: have ${kg(have)} KG, need ${kg(e.value)} KG');
        }
        // GST
        final coCode = '${co['state'] ?? '08 - Rajasthan'}'.substring(0, 2);
        final custCode = '${_cust['state'] ?? ''}'.length >= 2 ? '${_cust['state']}'.substring(0, 2) : coCode;
        final inter = custCode != coCode;
        double taxable = 0, cgst = 0, sgst = 0, igst = 0;
        final outLines = <Map<String, dynamic>>[];
        for (final l in _lines) {
          final t = r2(n(l['kg']) * n(l['rate']));
          final tax = r2(t * n(l['gst']) / 100);
          taxable += t;
          if (inter) {
            igst += tax;
          } else {
            cgst += r2(tax / 2);
            sgst += r2(tax / 2);
          }
          outLines.add({...l, 'taxable': t});
        }
        final raw = taxable + cgst + sgst + igst;
        final grand = raw.roundToDouble();
        final seq = (cSnap.data()?['last'] is num ? (cSnap.data()!['last'] as num).toInt() : 0) + 1;
        final invNo = '${co['invoicePrefix'] ?? 'BR'}/$fyr/${seq.toString().padLeft(4, '0')}';
        final ref = Db.c('invoices').doc();
        tx.set(cRef, {'last': seq}, SetOptions(merge: true));
        tx.set(ref, {
          'invoiceNo': invNo, 'seq': seq, 'fy': fyr, 'date': _date,
          'customerId': _custId, 'customerName': _cust['name'], 'customerGstin': _cust['gstin'] ?? '',
          'customerAddress': _cust['address'] ?? '', 'customerState': _cust['state'] ?? '', 'interstate': inter,
          'lines': outLines, 'taxable': r2(taxable), 'cgst': r2(cgst), 'sgst': r2(sgst), 'igst': r2(igst),
          'roundOff': r2(grand - raw), 'grandTotal': grand,
          'vehicleNo': _vehicle.text.trim(), 'transporter': _transporter.text.trim(), 'lrNo': _lr.text.trim(),
          'slipNo': _slip.text.trim(), 'grossKg': n(_gross.text), 'tareKg': n(_tare.text),
          'netKg': n(_gross.text) - n(_tare.text), 'status': 'Created',
          'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email,
        });
        for (final l in outLines) {
          if (l['sourceType'] == 'tank') {
            Db.tankMove(tx, tankId: '${l['sourceId']}', qty: -n(l['kg']), type: 'sale', refType: 'invoice', refId: ref.id, note: invNo);
          } else {
            Db.stockMove(tx, godownId: '${l['sourceId']}', item: l['product'] == 'Mustard Khali' ? 'khali' : 'doc',
                qty: -n(l['kg']), type: 'sale', refType: 'invoice', refId: ref.id, note: invNo);
          }
        }
        Db.audit(tx, 'invoice', '$invNo ${_cust['name']} ${money(grand)}', refId: ref.id);
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', '').replaceFirst('[cloud_firestore/unavailable] ', 'Internet is required to create an invoice (for the invoice number). '));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New GST invoice')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: Db.c('customers').orderBy('name').snapshots(),
              builder: (context, s) {
                final docs = s.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  value: docs.any((d) => d.id == _custId) ? _custId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Customer (add new customers in Masters)'),
                  items: docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d['name']}'))).toList(),
                  onChanged: (id) => setState(() {
                    _custId = id;
                    _cust = docs.firstWhere((d) => d.id == id).data();
                  }),
                );
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Invoice date'), child: Text(_date)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Add item')),
            ]),
            for (var i = 0; i < _lines.length; i++)
              Card(
                child: ListTile(
                  title: Text('${_lines[i]['product']} - ${kg(_lines[i]['kg'])} KG @ ${_lines[i]['rate']}'),
                  subtitle: Text('HSN ${_lines[i]['hsn']}  GST ${_lines[i]['gst']}%  from ${_lines[i]['sourceName']}'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
                ),
              ),
            const SizedBox(height: 12),
            Text('Dispatch & weighbridge (external weighbridge: type the weights)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: _vehicle, decoration: const InputDecoration(labelText: 'Vehicle no.')),
            const SizedBox(height: 10),
            TextField(controller: _transporter, decoration: const InputDecoration(labelText: 'Transporter')),
            const SizedBox(height: 10),
            TextField(controller: _lr, decoration: const InputDecoration(labelText: 'LR / GR no.')),
            const SizedBox(height: 10),
            TextField(controller: _slip, decoration: const InputDecoration(labelText: 'Weighment slip no.')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _gross, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gross wt (KG)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _tare, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tare wt (KG)'))),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Create invoice (needs internet)'),
            ),
            const SizedBox(height: 8),
            const Text('GST type (CGST+SGST or IGST) is chosen automatically from the customer state. '
                'Check HSN codes and GST rates with your CA before first use. E-invoice IRN / e-way bill are not generated by this app.',
                style: TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
