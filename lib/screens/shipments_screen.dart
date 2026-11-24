import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/form_page.dart';
import '../widgets/live_map.dart';
import 'track_page.dart';

class ShipmentsScreen extends StatelessWidget {
  final AppState app;
  const ShipmentsScreen({super.key, required this.app});

  Future<void> _create(Map<String, dynamic> v) async {
    final inv = (v['_invoice'] as Map<String, dynamic>?) ?? {};
    final ref = Db.c('shipments').doc();
    final vehicle = '${v['vehicleNo'] ?? ''}'.isEmpty ? '${inv['vehicleNo'] ?? ''}' : '${v['vehicleNo']}';
    final b = Db.fs.batch();
    final ts = FieldValue.serverTimestamp();
    b.set(ref, {
      'invoiceId': v['invoice'], 'invoiceNo': v['invoiceName'], 'customerName': inv['customerName'],
      'customerAddress': inv['customerAddress'] ?? '', 'driverUid': v['driver'], 'driverName': v['driverName'],
      'vehicleNo': vehicle, 'note': v['note'] ?? '', 'status': 'Pending',
      'lastLat': null, 'lastLng': null, 'lastAt': null, 'createdAt': ts, 'createdBy': Db.email,
    });
    b.set(Db.c('tracking').doc(ref.id), {
      'invoiceNo': v['invoiceName'], 'customerName': inv['customerName'], 'vehicleNo': vehicle,
      'status': 'Pending', 'lastLat': null, 'lastLng': null, 'lastAt': null, 'createdAt': ts,
    });
    b.update(Db.c('invoices').doc('${v['invoice']}'), {'status': 'Dispatched', 'updatedAt': ts});
    Db.audit(b, 'shipment', '${v['invoiceName']} assigned to ${v['driverName']}', refId: ref.id);
    await Db.commit(b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: app.isBiz
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New shipment'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FormPage(
                    title: 'New shipment',
                    fields: const [
                      FieldDef('invoice', 'Invoice (only invoices not yet dispatched)', FT.doc,
                          coll: 'invoices', labelKey: 'invoiceNo', where: {'status': 'Created'}),
                      FieldDef('driver', 'Driver', FT.doc, coll: 'users', where: {'role': 'driver'}),
                      FieldDef('vehicleNo', 'Vehicle no. (blank = from invoice)', FT.text, required: false),
                      FieldDef('note', 'Note for driver', FT.multiline, required: false),
                    ],
                    onSave: _create,
                  ),
                ),
              ),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.c('shipments').orderBy('createdAt', descending: true).limit(200).snapshots(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.docs.isEmpty) return const Center(child: Text('No shipments yet'));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            for (final d in s.data!.docs)
              Card(
                child: ListTile(
                  leading: Icon(d['status'] == 'Delivered' ? Icons.check_circle : Icons.local_shipping_outlined,
                      color: d['status'] == 'Delivered' ? Colors.green : null),
                  title: Text('${d['invoiceNo']} - ${d['customerName']}'),
                  subtitle: Text('Driver ${d['driverName']} - ${d['vehicleNo'] ?? '-'} - ${d['status']} - last ${ts(d['lastAt'])}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShipmentDetail(id: d.id))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class ShipmentDetail extends StatelessWidget {
  final String id;
  const ShipmentDetail({super.key, required this.id});

  Future<void> _share(BuildContext context, String link, String invoiceNo) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking link copied')));
    }
    try {
      await Share.share('Track your B.R. Edible Oils delivery ($invoiceNo): $link');
    } catch (_) {}
  }

  void _edit(BuildContext context, Map<String, dynamic> m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          title: 'Change driver / vehicle',
          initial: {'driver': m['driverUid'], 'driverName': m['driverName'], 'vehicleNo': m['vehicleNo'], 'note': m['note']},
          fields: const [
            FieldDef('driver', 'Driver', FT.doc, coll: 'users', where: {'role': 'driver'}),
            FieldDef('vehicleNo', 'Vehicle no.', FT.text, required: false),
            FieldDef('note', 'Note for driver', FT.multiline, required: false),
          ],
          onSave: (v) async {
            final ts = FieldValue.serverTimestamp();
            final b = Db.fs.batch();
            b.update(Db.c('shipments').doc(id), {'driverUid': v['driver'], 'driverName': v['driverName'], 'vehicleNo': v['vehicleNo'], 'note': v['note'], 'updatedAt': ts});
            b.update(Db.c('tracking').doc(id), {'vehicleNo': v['vehicleNo'], 'updatedAt': ts});
            Db.audit(b, 'shipment', '${m['invoiceNo']}: driver/vehicle changed to ${v['driverName']} / ${v['vehicleNo']}', refId: id);
            await Db.commit(b);
          },
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this shipment?'),
        content: const Text('The shipment and its customer tracking link are deleted. The invoice goes back to "not dispatched". A note is kept in the Audit trail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final b = Db.fs.batch();
    b.delete(Db.c('shipments').doc(id));
    b.delete(Db.c('tracking').doc(id));
    if (m['status'] != 'Delivered' && '${m['invoiceId'] ?? ''}'.isNotEmpty) {
      b.update(Db.c('invoices').doc('${m['invoiceId']}'), {'status': 'Created', 'updatedAt': FieldValue.serverTimestamp()});
    }
    Db.audit(b, 'delete', 'shipment ${m['invoiceNo']} (${m['customerName']}, driver ${m['driverName']}, ${m['status']}) removed', refId: id);
    await Db.commit(b);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final base = app.trackingBase;
    final link = '$base/#/track/$id';
    return Scaffold(
      appBar: AppBar(title: const Text('Shipment tracking')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Db.c('shipments').doc(id).snapshots(),
        builder: (context, s) {
          final m = s.data?.data();
          if (m == null) return const Center(child: CircularProgressIndicator());
          final lat = m['lastLat'], lng = m['lastLng'];
          final has = lat is num && lng is num;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${m['invoiceNo']} - ${m['customerName']}', style: Theme.of(context).textTheme.titleLarge),
            Text('Driver: ${m['driverName']}   Vehicle: ${m['vehicleNo'] ?? '-'}'),
            Text('Status: ${m['status']}'),
            Text('Last location: ${ts(m['lastAt'])}'),
            if (m['status'] == 'Delivered') Text('Delivered: ${ts(m['deliveredAt'])}  ${m['deliveryNote'] ?? ''}'),
            const SizedBox(height: 12),
            if (has) LiveMap(lat: n(lat), lng: n(lng)) else const Text('No location yet - the driver has not started the trip.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _share(context, link, '${m['invoiceNo']}'),
                icon: const Icon(Icons.share),
                label: const Text('Share tracking link with customer'),
              ),
              if (has)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Google Maps'),
                ),
              if (app.isBiz && m['status'] != 'Delivered')
                OutlinedButton.icon(
                  onPressed: () => _edit(context, m),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Change driver / vehicle'),
                ),
              if (app.isAdmin)
                TextButton.icon(
                  onPressed: () => _remove(context, m),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove shipment'),
                ),
            ]),
            const SizedBox(height: 8),
            SelectableText(link, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            const Text('The customer link works only after the web app is published (README: "Publish the web app / tracking link").',
                style: TextStyle(fontSize: 11)),
          ]);
        },
      ),
    );
  }
}
