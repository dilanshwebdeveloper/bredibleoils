import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/export.dart';
import '../core/fmt.dart';

const _collections = ['settings', 'users', 'suppliers', 'customers', 'employees', 'labour', 'attendanceRoster',
  'machines', 'godowns', 'tanks', 'stock', 'stockLedger', 'tankLedger', 'purchases', 'docPurchases',
  'supplierPayments', 'expenses', 'productions', 'qcRecords', 'attendance', 'labourAttendance', 'invoices',
  'shipments', 'tracking', 'payroll', 'counters', 'auditLogs'];

dynamic _clean(dynamic v) {
  if (v is Timestamp) return {'__ts': v.toDate().toIso8601String()};
  if (v is Map) return v.map((k, x) => MapEntry('$k', _clean(x)));
  if (v is List) return v.map(_clean).toList();
  return v;
}

dynamic _revive(dynamic v) {
  if (v is Map) {
    if (v.length == 1 && v.containsKey('__ts')) return Timestamp.fromDate(DateTime.parse('${v['__ts']}'));
    return v.map((k, x) => MapEntry('$k', _revive(x)));
  }
  if (v is List) return v.map(_revive).toList();
  return v;
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';

  Future<void> _backup() async {
    setState(() { _busy = true; _status = 'Reading data...'; });
    try {
      final out = <String, dynamic>{'exportedAt': DateTime.now().toIso8601String(), 'project': 'br-industriestonk'};
      var total = 0;
      for (final c in _collections) {
        final s = await Db.c(c).get();
        out[c] = {for (final d in s.docs) d.id: _clean(d.data())};
        total += s.docs.length;
        setState(() => _status = 'Read $c (${s.docs.length})');
      }
      if (!mounted) return;
      await saveOrShare(context, 'BR_ERP_backup_${today()}.json', const JsonEncoder.withIndent(' ').convert(out), mime: 'application/json');
      setState(() => _status = 'Backup created: $total records.');
    } catch (e) {
      setState(() => _status = 'Backup failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text('Only records that are MISSING are added. Existing records are never overwritten. '
            'Login accounts (passwords) are not restored - recreate those in Users & Roles.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore missing records')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _status = 'Restoring...'; });
    var added = 0, skipped = 0;
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      for (final c in _collections) {
        final m = data[c];
        if (m is! Map) continue;
        for (final e in m.entries) {
          final ref = Db.c(c).doc('${e.key}');
          try {
            if ((await ref.get()).exists) {
              skipped++;
              continue;
            }
            await ref.set(Map<String, dynamic>.from(_revive(e.value) as Map));
            added++;
          } catch (_) {
            skipped++;
          }
        }
        setState(() => _status = 'Restoring... $c done (added $added, skipped $skipped)');
      }
      setState(() => _status = 'Restore finished: $added records added, $skipped skipped (already present or not allowed).');
    } catch (e) {
      setState(() => _status = 'Restore failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Backup & restore', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Backup downloads every record as one JSON file (Windows: Documents\\BR_ERP_Exports; Android/Web: save/share sheet). '
                'Do this weekly and keep copies off the PC. Restore adds back only records that are missing.'),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(onPressed: _busy ? null : _backup, icon: const Icon(Icons.cloud_download_outlined), label: const Text('Create backup now')),
              OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Restore from backup file')),
            ]),
            if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_status)),
          ]),
        ),
      ),
    ]);
  }
}
