import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/crud_screen.dart';
import '../widgets/form_page.dart';

class TankGrid extends StatelessWidget {
  final bool interactive;
  const TankGrid({super.key, this.interactive = false});

  @override
  Widget build(BuildContext context) {
    return DensityBuilder(
      builder: (context, dens) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.c('tanks').orderBy('order').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.docs.isEmpty) return const SetupHelp();
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final d in s.data!.docs)
                SizedBox(
                  width: 220,
                  child: Card(
                    child: InkWell(
                      onTap: interactive ? () => _movement(context, d.id, d.data(), dens) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _tank(context, d.data(), dens),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tank(BuildContext context, Map<String, dynamic> m, double dens) {
    final cap = n(m['capacityL']);
    final litres = n(m['oilKg']) / dens;
    final pct = cap <= 0 ? 0.0 : (litres / cap).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: pct, minHeight: 10, borderRadius: BorderRadius.circular(6)),
      const SizedBox(height: 8),
      Text('${kg(litres)} L of ${kg(cap)} L (${(pct * 100).toStringAsFixed(0)}%)'),
      Text('${kg(m['oilKg'])} KG', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  void _movement(BuildContext context, String id, Map<String, dynamic> tank, double dens) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          title: 'Tank movement: ${tank['name']}',
          fields: const [
            FieldDef('type', 'Movement', FT.choice, options: ['Fill (+)', 'Empty (-)']),
            FieldDef('kg', 'Quantity (KG)', FT.number),
            FieldDef('reason', 'Reason / reference', FT.text),
          ],
          onSave: (v) async {
            final q = n(v['kg']);
            if (q <= 0) throw Exception('Quantity must be more than 0');
            final fill = '${v['type']}'.startsWith('Fill');
            final cur = n(tank['oilKg']);
            if (fill && (cur + q) / dens > n(tank['capacityL'])) throw Exception('Tank capacity would be exceeded');
            if (!fill && q > cur) throw Exception('Tank does not have that much oil');
            final b = Db.fs.batch();
            Db.tankMove(b, tankId: id, qty: fill ? q : -q, type: fill ? 'fill' : 'empty', refType: 'manual', note: '${v['reason']}');
            Db.audit(b, 'tank-movement', '${tank['name']} ${fill ? '+' : '-'}${kg(q)} KG: ${v['reason']}', refId: id);
            await Db.commit(b);
          },
        ),
      ),
    );
  }
}

class TanksScreen extends StatelessWidget {
  const TanksScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Tanks (tap to fill / empty)'), Tab(text: 'Movement history')]),
        Expanded(
          child: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(16), children: const [TankGrid(interactive: true)]),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: Db.c('tankLedger').orderBy('at', descending: true).limit(200).snapshots(),
              builder: (context, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(children: [
                  for (final d in s.data!.docs)
                    ListTile(
                      leading: Icon(n(d['qtyKg']) >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                          color: n(d['qtyKg']) >= 0 ? Colors.green : Colors.red),
                      title: Text('${d['tankId']}  ${n(d['qtyKg']) >= 0 ? '+' : ''}${kg(d['qtyKg'])} KG'),
                      subtitle: Text('${d['day']} - ${d['type']} (${d['refType']}) ${d['note'] ?? ''}'),
                    ),
                ]);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Shown when the 10 machines / godowns / 7 tanks have not been created yet.
class SetupHelp extends StatefulWidget {
  const SetupHelp({super.key});
  @override
  State<SetupHelp> createState() => _SetupHelpState();
}

class _SetupHelpState extends State<SetupHelp> {
  bool _busy = false;
  String _msg = '';

  Future<void> _run() async {
    setState(() { _busy = true; _msg = ''; });
    final e = await Db.seedFactory();
    if (mounted) setState(() { _busy = false; _msg = e == null ? 'Done. The tanks will appear in a moment.' : 'Failed: $e'; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('No tanks, machines or godowns yet. The Admin can create the default set-up now (internet needed).'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _run,
        icon: const Icon(Icons.build_circle_outlined),
        label: const Text('Create default set-up now'),
      ),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: SelectableText(_msg)),
    ]);
  }
}
