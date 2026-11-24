import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/db.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../widgets/live_map.dart';

/// Public page opened by the customer from the tracking link. No login.
class TrackApp extends StatelessWidget {
  final String id;
  const TrackApp({super.key, required this.id});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Track delivery',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: TrackPage(id: id),
      );
}

String ts(dynamic v) => v is Timestamp ? DateFormat('dd MMM yyyy, hh:mm a').format(v.toDate()) : '-';

class TrackPage extends StatelessWidget {
  final String id;
  const TrackPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track your delivery')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Db.c('tracking').doc(id).snapshots(),
        builder: (context, s) {
          if (s.hasError) return const Center(child: Text('This tracking link is not valid.'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final m = s.data!.data();
          if (m == null) return const Center(child: Text('This tracking link is not valid.'));
          final lat = m['lastLat'], lng = m['lastLng'];
          final has = lat is num && lng is num;
          final status = '${m['status']}';
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Image.asset('assets/logo.jpg', height: 90),
                const SizedBox(height: 8),
                Text('B.R. Edible Oils Pvt. Ltd.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('Invoice ${m['invoiceNo']}', style: Theme.of(context).textTheme.titleLarge),
                Text('For: ${m['customerName']}'),
                Text('Vehicle: ${m['vehicleNo'] ?? '-'}'),
                const SizedBox(height: 8),
                Chip(label: Text(status == 'Pending' ? 'Dispatch being prepared' : status == 'In transit' ? 'On the way' : 'Delivered')),
                if (status == 'Delivered') Text('Delivered on ${ts(m['deliveredAt'])}'),
                if (status != 'Delivered') Text('Last location update: ${ts(m['lastAt'])}'),
                const SizedBox(height: 12),
                if (has) LiveMap(lat: n(lat), lng: n(lng)) else const Text('Live location will appear here once the driver starts the trip.'),
                if (has)
                  TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Google Maps'),
                    onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
