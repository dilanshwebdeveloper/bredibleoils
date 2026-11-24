import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/tracking_service.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  String _perm = 'checking'; // ok | denied | forever | off

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(ask: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool ask = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _perm = 'off');
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      final r = (p == LocationPermission.whileInUse || p == LocationPermission.always)
          ? 'ok'
          : p == LocationPermission.deniedForever ? 'forever' : 'denied';
      if (mounted) setState(() => _perm = r);
    } catch (_) {
      if (mounted) setState(() => _perm = 'ok');
    }
  }

  Widget _banner() {
    final text = _perm == 'off'
        ? 'Phone GPS (location) is OFF. Turn it on so the office can see your shipment.'
        : _perm == 'forever'
            ? 'Location permission is blocked. Open app settings and allow Location for this app.'
            : 'This app needs your location to share the shipment with the office. Please allow it.';
    final label = _perm == 'off' ? 'Turn on GPS' : _perm == 'forever' ? 'Open app settings' : 'Allow location';
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              if (_perm == 'off') {
                await Geolocator.openLocationSettings();
              } else if (_perm == 'forever') {
                await Geolocator.openAppSettings();
              } else {
                await _check(ask: true);
              }
            },
            child: Text(label),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver: ${a.profile?.name ?? ''}'),
        actions: [IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: a.signOut)],
      ),
      body: Column(children: [
        if (_perm != 'ok' && _perm != 'checking') Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: _banner()),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Db.c('shipments').where('driverUid', isEqualTo: Db.uid).snapshots(),
            builder: (context, s) {
              if (s.hasError) return Center(child: Text('${s.error}'));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final docs = s.data!.docs.toList()
                ..sort((x, y) {
                  final dx = x.data()['status'] == 'Delivered' ? 1 : 0, dy = y.data()['status'] == 'Delivered' ? 1 : 0;
                  return dx.compareTo(dy);
                });
              if (docs.isEmpty) return const Center(child: Text('No shipments assigned to you yet.'));
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final d in docs)
                  Card(
                    child: ListTile(
                      leading: Icon(d.data()['status'] == 'Delivered' ? Icons.check_circle : Icons.local_shipping,
                          color: d.data()['status'] == 'Delivered' ? Colors.green : null),
                      title: Text('${d['invoiceNo']} - ${d['customerName']}'),
                      subtitle: Text('${d['customerAddress'] ?? ''}\nVehicle ${d['vehicleNo'] ?? '-'} - ${d['status']}'),
                      isThreeLine: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverShipmentPage(id: d.id))),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class DriverShipmentPage extends StatefulWidget {
  final String id;
  const DriverShipmentPage({super.key, required this.id});
  @override
  State<DriverShipmentPage> createState() => _DriverShipmentPageState();
}

class _DriverShipmentPageState extends State<DriverShipmentPage> {
  bool _busy = false, _resumed = false;
  String? _err;

  Future<void> _update(Map<String, dynamic> shipment, Map<String, dynamic> tracking) async {
    final b = Db.fs.batch();
    b.update(Db.c('shipments').doc(widget.id), {...shipment, 'updatedAt': FieldValue.serverTimestamp()});
    b.update(Db.c('tracking').doc(widget.id), {...tracking, 'updatedAt': FieldValue.serverTimestamp()});
    await Db.commit(b);
  }

  Future<void> _start() async {
    setState(() { _busy = true; _err = null; });
    final e = await TrackingService.start(widget.id);
    if (e != null) {
      setState(() { _err = e; _busy = false; });
      return;
    }
    try {
      await _update({'status': 'In transit'}, {'status': 'In transit'});
    } catch (x) {
      _err = '$x';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deliver() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delivered successfully?'),
        content: TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, delivered')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _err = null; });
    try {
      await TrackingService.stop();
      await _update(
        {'status': 'Delivered', 'deliveredAt': FieldValue.serverTimestamp(), 'deliveryNote': note.text.trim()},
        {'status': 'Delivered', 'deliveredAt': FieldValue.serverTimestamp()},
      );
    } catch (x) {
      _err = '$x';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shipment')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Db.c('shipments').doc(widget.id).snapshots(),
        builder: (context, s) {
          final m = s.data?.data();
          if (m == null) return const Center(child: CircularProgressIndicator());
          final status = '${m['status']}';
          if (status == 'In transit' && !_resumed && TrackingService.active != widget.id) {
            _resumed = true; // app was reopened mid-trip: continue sharing location
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final e = await TrackingService.start(widget.id);
              if (e != null && mounted) setState(() => _err = e);
            });
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${m['invoiceNo']}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Customer: ${m['customerName']}'),
            Text('Address: ${m['customerAddress'] ?? '-'}'),
            Text('Vehicle: ${m['vehicleNo'] ?? '-'}'),
            if ('${m['note'] ?? ''}'.isNotEmpty) Text('Note: ${m['note']}'),
            const SizedBox(height: 10),
            Chip(label: Text('Status: $status')),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (status != 'Delivered')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('${m['customerAddress'] ?? m['customerName']}')}&travelmode=driving'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navigate in Google Maps'),
                ),
              ),
            const SizedBox(height: 16),
            if (status == 'Pending')
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start trip & share my location'),
              ),
            if (status == 'In transit') ...[
              const Text('Your location is being shared with the office. Keep this phone\'s GPS and internet on.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _deliver,
                icon: const Icon(Icons.check),
                label: const Text('Mark delivered successfully'),
              ),
            ],
            if (status == 'Delivered') const Text('Delivered. Thank you!'),
          ]);
        },
      ),
    );
  }
}
