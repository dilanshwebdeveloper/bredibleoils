import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/form_page.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  String _units(dynamic v) => '${kg(v)} KG  |  ${kg(n(v) / 100)} Qtl  |  ${kg(n(v) / 1000)} MT';

  Future<void> _transfer(Map<String, dynamic> v) async {
    final q = n(v['kg']);
    if (q <= 0) throw Exception('Quantity must be more than 0');
    if (v['from'] == v['to']) throw Exception('From and To godown must be different');
    final item = '${v['item']}';
    final from = (v['_from'] as Map<String, dynamic>?) ?? {};
    final to = (v['_to'] as Map<String, dynamic>?) ?? {};
    if (item != 'doc' && (from['type'] != item || to['type'] != item)) {
      throw Exception('Seed moves only between seed godowns; Khali only between Khali godowns');
    }
    final have = await Db.c('stock').doc('${v['from']}__$item').get();
    if (n(have.data()?['qtyKg']) < q) throw Exception('Not enough stock in the source godown');
    final b = Db.fs.batch();
    Db.stockMove(b, godownId: '${v['from']}', item: item, qty: -q, type: 'transfer-out', refType: 'transfer', note: 'to ${v['toName']}');
    Db.stockMove(b, godownId: '${v['to']}', item: item, qty: q, type: 'transfer-in', refType: 'transfer', note: 'from ${v['fromName']}');
    Db.audit(b, 'transfer', '$item ${kg(q)} KG ${v['fromName']} -> ${v['toName']}');
    await Db.commit(b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Godown transfer'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FormPage(
              title: 'Godown transfer',
              fields: const [
                FieldDef('item', 'Item', FT.choice, options: ['seed', 'khali', 'doc']),
                FieldDef('from', 'From godown', FT.doc, coll: 'godowns'),
                FieldDef('to', 'To godown', FT.doc, coll: 'godowns'),
                FieldDef('kg', 'Quantity (KG)', FT.number),
              ],
              onSave: _transfer,
            ),
          ),
        ),
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'Live balance'), Tab(text: 'Stock history')]),
          Expanded(
            child: TabBarView(children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: Db.c('godowns').orderBy('order').snapshots(),
                builder: (context, gs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: Db.c('stock').snapshots(),
                  builder: (context, ss) {
                    if (!gs.hasData || !ss.hasData) return const Center(child: CircularProgressIndicator());
                    final bal = {for (final d in ss.data!.docs) d.id: n(d.data()['qtyKg'])};
                    double total(String item) => ss.data!.docs
                        .where((d) => d.data()['item'] == item)
                        .fold<double>(0, (s, d) => s + n(d.data()['qtyKg']));
                    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                      Card(child: ListTile(title: const Text('Total mustard seed'), subtitle: Text(_units(total('seed'))))),
                      Card(child: ListTile(title: const Text('Total Khali'), subtitle: Text(_units(total('khali'))))),
                      if (total('doc') != 0)
                        Card(child: ListTile(title: const Text('Total DOC (trading)'), subtitle: Text(_units(total('doc'))))),
                      const SizedBox(height: 8),
                      for (final g in gs.data!.docs)
                        Card(
                          child: ListTile(
                            title: Text('${g.data()['name']}'),
                            subtitle: Text(g.data()['type'] == 'khali'
                                ? 'Khali: ${_units(bal['${g.id}__khali'] ?? 0)}'
                                : 'Seed: ${_units(bal['${g.id}__seed'] ?? 0)}'),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Oil stock is kept per tank (see Oil Tanks). KG is the base unit everywhere.'),
                      ),
                    ]);
                  },
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: Db.c('stockLedger').orderBy('at', descending: true).limit(200).snapshots(),
                builder: (context, s) {
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView(children: [
                    for (final d in s.data!.docs)
                      ListTile(
                        leading: Icon(n(d['qtyKg']) >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                            color: n(d['qtyKg']) >= 0 ? Colors.green : Colors.red),
                        title: Text('${d['godownId']} - ${d['item']}: ${n(d['qtyKg']) >= 0 ? '+' : ''}${kg(d['qtyKg'])} KG'),
                        subtitle: Text('${d['day']} - ${d['type']} (${d['refType']}) ${d['note'] ?? ''}'),
                      ),
                  ]);
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
