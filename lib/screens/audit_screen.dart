import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/db.dart';

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Db.c('auditLogs').orderBy('at', descending: true).limit(300).snapshots(),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(children: [
          for (final d in s.data!.docs)
            ListTile(
              dense: true,
              title: Text('${d['action']}: ${d['detail']}'),
              subtitle: Text('${d['email']} - ${d.data()['at'] is Timestamp ? DateFormat('dd MMM yyyy HH:mm').format((d.data()['at'] as Timestamp).toDate()) : 'syncing...'}'),
            ),
        ]);
      },
    );
  }
}
