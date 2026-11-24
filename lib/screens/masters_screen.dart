import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../widgets/crud_screen.dart';
import '../widgets/form_page.dart';

/// Saves an employee / labour master AND its name in the attendance roster
/// (so the attendance-only 'employee' login never needs access to salaries).
Future<void> saveRoster(String coll, String type, Map<String, dynamic> v, String? id) async {
  final data = Map<String, dynamic>.from(v)..removeWhere((k, _) => k.startsWith('_'));
  final b = Db.fs.batch();
  final ref = id == null ? Db.c(coll).doc() : Db.c(coll).doc(id);
  if (id == null) {
    b.set(ref, {...data, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email});
  } else {
    b.update(ref, {...data, 'updatedAt': FieldValue.serverTimestamp()});
  }
  b.set(Db.c('attendanceRoster').doc(ref.id), {'name': data['name'], 'code': data['code'] ?? '', 'type': type}, SetOptions(merge: true));
  Db.audit(b, id == null ? 'create' : 'update', '$coll: ${data['name']}', refId: ref.id);
  await Db.commit(b);
}

class MastersScreen extends StatelessWidget {
  final AppState app;
  const MastersScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final items = <(String, IconData, CrudScreen)>[
      ('Suppliers', Icons.local_shipping_outlined, CrudScreen(
        title: 'Suppliers', collection: 'suppliers', orderBy: 'name', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isBiz, canAdd: app.isBiz,
        fields: const [
          FieldDef('name', 'Supplier name', FT.text),
          FieldDef('phone', 'Phone', FT.text, required: false),
          FieldDef('gstin', 'GSTIN', FT.text, required: false),
          FieldDef('address', 'Address', FT.multiline, required: false),
        ],
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => '${m['phone'] ?? ''} ${m['gstin'] ?? ''}',
      )),
      ('Customers', Icons.people_outline, CrudScreen(
        title: 'Customers', collection: 'customers', orderBy: 'name', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isBiz, canAdd: app.isBiz,
        fields: const [
          FieldDef('name', 'Customer name', FT.text),
          FieldDef('gstin', 'GSTIN (blank if unregistered)', FT.text, required: false),
          FieldDef('state', 'State (place of supply)', FT.choice, options: indianStates),
          FieldDef('address', 'Billing address', FT.multiline),
          FieldDef('phone', 'Phone (WhatsApp)', FT.text, required: false),
          FieldDef('email', 'Email', FT.text, required: false),
        ],
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => '${m['state'] ?? ''} - ${m['gstin'] ?? 'Unregistered'}',
      )),
      ('Employees', Icons.badge_outlined, CrudScreen(
        title: 'Employees', collection: 'employees', alsoDelete: (id) => [Db.c('attendanceRoster').doc(id)], orderBy: 'name', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isMgr, canAdd: app.isMgr,
        fields: const [
          FieldDef('name', 'Name', FT.text),
          FieldDef('code', 'Employee code', FT.text, required: false),
          FieldDef('designation', 'Designation', FT.text, required: false),
          FieldDef('phone', 'Phone', FT.text, required: false),
          FieldDef('shift', 'Usual shift', FT.choice, options: ['Shift A (Day)', 'Shift B (Night)', 'General']),
          FieldDef('monthlySalary', 'Monthly salary', FT.number),
          FieldDef('pfApplicable', 'PF applicable?', FT.choice, options: ['No', 'Yes'], initial: 'No'),
          FieldDef('esiApplicable', 'ESI applicable?', FT.choice, options: ['No', 'Yes'], initial: 'No'),
        ],
        customSave: (v, id) => saveRoster('employees', 'staff', v, id),
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => '${m['designation'] ?? ''} - ${m['shift']} - ${money(m['monthlySalary'])}',
      )),
      ('Labour (daily wage workers)', Icons.engineering_outlined, CrudScreen(
        title: 'Labour', collection: 'labour', alsoDelete: (id) => [Db.c('attendanceRoster').doc(id)], orderBy: 'name', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isMgr, canAdd: app.isMgr,
        fields: const [
          FieldDef('name', 'Name', FT.text),
          FieldDef('code', 'Labour code', FT.text, required: false),
          FieldDef('contractor', 'Contractor / gang', FT.text, required: false),
          FieldDef('phone', 'Phone', FT.text, required: false),
          FieldDef('shift', 'Usual shift', FT.choice, options: ['Shift A (Day)', 'Shift B (Night)', 'General']),
          FieldDef('dailyWage', 'Daily wage', FT.number),
        ],
        customSave: (v, id) => saveRoster('labour', 'labour', v, id),
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => '${m['contractor'] ?? ''} - ${m['shift']} - ${money(m['dailyWage'])}/day',
      )),
      ('Machines (10)', Icons.precision_manufacturing_outlined, CrudScreen(
        title: 'Machines', collection: 'machines', orderBy: 'order', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isMgr, canAdd: app.isAdmin,
        fields: const [
          FieldDef('name', 'Machine name', FT.text),
          FieldDef('code', 'Code', FT.text),
          FieldDef('status', 'Status', FT.choice, options: ['Active', 'Under maintenance', 'Inactive']),
          FieldDef('order', 'Display order', FT.number),
        ],
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => '${m['code']} - ${m['status']}',
      )),
      ('Godowns (5 seed + 1 Khali)', Icons.warehouse_outlined, CrudScreen(
        title: 'Godowns', collection: 'godowns', deleteGuard: (id, m) async {
          final st = await Db.c('stock').where('godownId', isEqualTo: id).get();
          final tot = st.docs.fold<double>(0, (x, d) => x + n(d.data()['qtyKg']));
          return tot > 0 ? 'This godown still has stock. Move it out first.' : null;
        }, orderBy: 'order', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isMgr, canAdd: app.isAdmin,
        fields: const [
          FieldDef('name', 'Godown name', FT.text),
          FieldDef('type', 'Type', FT.choice, options: ['seed', 'khali']),
          FieldDef('order', 'Display order', FT.number),
        ],
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => 'Type: ${m['type']}',
      )),
      ('Oil tanks (7 x 25,000 L)', Icons.oil_barrel_outlined, CrudScreen(
        title: 'Oil tanks', collection: 'tanks', deleteGuard: (id, m) async => n(m['oilKg']) > 0 ? 'This tank still has oil. Empty it first.' : null, orderBy: 'order', showAppBar: true, canDelete: app.isAdmin, canEdit: app.isMgr, canAdd: app.isAdmin,
        fields: const [
          FieldDef('name', 'Tank name', FT.text),
          FieldDef('capacityL', 'Capacity (litres)', FT.number),
          FieldDef('order', 'Display order', FT.number),
        ],
        titleOf: (m) => '${m['name']}', subtitleOf: (m) => 'Capacity ${kg(m['capacityL'])} L',
      )),
    ];
    final visible = app.isMgr ? items : items.take(2).toList(); // accountants: suppliers & customers only
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final it in visible)
        Card(
          child: ListTile(
            leading: Icon(it.$2),
            title: Text(it.$1),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => it.$3)),
          ),
        ),
    ]);
  }
}
