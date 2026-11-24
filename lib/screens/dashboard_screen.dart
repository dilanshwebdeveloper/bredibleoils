import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/crud_screen.dart';
import 'tanks_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = today();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Metric('Seed stock', Icons.grass, Db.c('stock').where('item', isEqualTo: 'seed').snapshots(),
              (d) => '${kg(d.fold<double>(0, (s, e) => s + n(e.data()['qtyKg'])))} KG'),
          _Metric('Khali stock', Icons.inventory_2_outlined, Db.c('stock').where('item', isEqualTo: 'khali').snapshots(),
              (d) => '${kg(d.fold<double>(0, (s, e) => s + n(e.data()['qtyKg'])))} KG'),
          DensityBuilder(
            builder: (c, dens) => _Metric('Oil in tanks', Icons.oil_barrel, Db.c('tanks').snapshots(), (d) {
              final k = d.fold<double>(0, (s, e) => s + n(e.data()['oilKg']));
              return '${kg(k)} KG\n~${kg(k / dens)} L';
            }),
          ),
          _Metric("Today's seed crushed", Icons.precision_manufacturing,
              Db.c('productions').where('date', isEqualTo: t).snapshots(),
              (d) => '${kg(d.where((e) => e.data()['status'] != 'Voided').fold<double>(0, (s, e) => s + n(e.data()['seedKg'])))} KG'),
          _Metric("Today's oil produced", Icons.water_drop_outlined,
              Db.c('productions').where('date', isEqualTo: t).snapshots(),
              (d) => '${kg(d.where((e) => e.data()['status'] != 'Voided').fold<double>(0, (s, e) => s + n(e.data()['oilKg'])))} KG'),
          _Metric("Today's sales", Icons.receipt_long, Db.c('invoices').where('date', isEqualTo: t).snapshots(),
              (d) => money(d.where((e) => e.data()['status'] != 'Cancelled').fold<double>(0, (s, e) => s + n(e.data()['grandTotal'])))),
        ]),
        const SizedBox(height: 24),
        Text('Oil tanks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const TankGrid(),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final IconData icon;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) value;
  const _Metric(this.title, this.icon, this.stream, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(icon, size: 20), const SizedBox(width: 8), Expanded(child: Text(title))]),
                const SizedBox(height: 10),
                Text(s.hasData ? value(s.data!.docs) : '...',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
