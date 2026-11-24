import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import 'form_page.dart';

typedef Rec = Map<String, dynamic>;

/// Generic list + add/edit screen used by masters, QC, attendance, expenses, etc.
class CrudScreen extends StatelessWidget {
  final String title, collection;
  final List<FieldDef> fields;
  final String Function(Rec) titleOf, subtitleOf;
  final String? orderBy;
  final bool descending, canAdd, canEdit, showAppBar;
  final Future<void> Function(Rec values, String? id)? customSave;
  final Widget Function(BuildContext, Rec, String)? trailing;
  final bool canDelete;
  final Future<String?> Function(String id, Rec m)? deleteGuard;
  final List<DocumentReference<Map<String, dynamic>>> Function(String id)? alsoDelete;

  const CrudScreen({
    super.key,
    required this.title,
    required this.collection,
    required this.fields,
    required this.titleOf,
    required this.subtitleOf,
    this.orderBy,
    this.descending = false,
    this.canAdd = true,
    this.canEdit = false,
    this.showAppBar = false,
    this.customSave,
    this.trailing,
    this.canDelete = false,
    this.deleteGuard,
    this.alsoDelete,
  });

  Future<void> _defaultSave(Rec v, String? id, [Rec? old]) async {
    final data = Rec.from(v)..removeWhere((k, _) => k.startsWith('_'));
    var changes = '';
    if (old != null) {
      final ch = <String>[];
      for (final f in fields) {
        if ('${old[f.key] ?? ''}' != '${data[f.key] ?? ''}') ch.add('${f.label}: ${old[f.key] ?? ''} -> ${data[f.key] ?? ''}');
      }
      changes = ch.join('; ');
    }
    final b = Db.fs.batch();
    final ref = id == null ? Db.c(collection).doc() : Db.c(collection).doc(id);
    if (id == null) {
      b.set(ref, {...data, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email});
    } else {
      b.update(ref, {...data, 'updatedAt': FieldValue.serverTimestamp()});
    }
    Db.audit(b, id == null ? 'create' : 'update', '$collection: ${titleOf(data)}${changes.isEmpty ? '' : ' | changed: $changes'}', refId: ref.id);
    await Db.commit(b);
  }

  Widget? _trail(BuildContext context, Rec m, String id) {
    final kids = <Widget>[];
    if (trailing != null) {
      kids.add(trailing!(context, m, id));
    } else if (canEdit) {
      kids.add(const Icon(Icons.edit_outlined));
    }
    if (canDelete) {
      kids.add(IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, m, id)));
    }
    if (kids.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: kids);
  }

  String _snap(Rec m) {
    final parts = <String>[];
    m.forEach((k, v) {
      if (v is String || v is num || v is bool) parts.add('$k=$v');
    });
    final s = parts.join(', ');
    return s.length > 600 ? s.substring(0, 600) : s;
  }

  Future<void> _delete(BuildContext context, Rec m, String id) async {
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text('${titleOf(m)}\n\nIt is removed for good. A copy of its details is kept in the Audit trail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final why = deleteGuard == null ? null : await deleteGuard!(id, m);
    if (why != null) {
      msg.showSnackBar(SnackBar(content: Text(why)));
      return;
    }
    try {
      final b = Db.fs.batch();
      b.delete(Db.c(collection).doc(id));
      for (final r in (alsoDelete?.call(id) ?? const <DocumentReference<Map<String, dynamic>>>[])) {
        b.delete(r);
      }
      Db.audit(b, 'delete', '$collection: ${titleOf(m)} | ${_snap(m)}', refId: id);
      await Db.commit(b);
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _open(BuildContext context, String? id, Rec m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          title: id == null ? 'Add: $title' : 'Edit: $title',
          fields: fields,
          initial: m,
          onSave: (v) => customSave != null ? customSave!(v, id) : _defaultSave(v, id, id == null ? null : m),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = Db.c(collection);
    if (orderBy != null) q = q.orderBy(orderBy!, descending: descending);
    q = q.limit(500);
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(title)) : null,
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _open(context, null, {}), icon: const Icon(Icons.add), label: const Text('Add'))
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No records yet'));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();
              return Card(
                child: ListTile(
                  title: Text(titleOf(m)),
                  subtitle: Text(subtitleOf(m)),
                  trailing: _trail(context, m, d.id),
                  onTap: canEdit ? () => _open(context, d.id, m) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Simple tab container for modules with several lists.
class TabsScreen extends StatelessWidget {
  final Map<String, Widget> tabs;
  const TabsScreen(this.tabs, {super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: tabs.keys.map((k) => Tab(text: k)).toList()),
          Expanded(child: TabBarView(children: tabs.values.toList())),
        ],
      ),
    );
  }
}

/// Provides the configured oil density (kg per litre) to its builder.
class DensityBuilder extends StatelessWidget {
  final Widget Function(BuildContext, double density) builder;
  const DensityBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.c('settings').doc('company').snapshots(),
      builder: (context, s) {
        final d = s.data?.data()?['oilDensity'];
        final dens = (d is num && d > 0) ? d.toDouble() : 0.915;
        return builder(context, dens);
      },
    );
  }
}
