import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/crud_screen.dart';
import '../widgets/form_page.dart';

const shifts = ['Shift A (Day)', 'Shift B (Night)'];
const payModes = ['Cash', 'Bank', 'UPI', 'Cheque'];

String _vp(Rec m) => m['status'] == 'Voided' ? '[VOIDED] ' : '';

Future<String?> _needVoid(String id, Rec m) async =>
    m['status'] == 'Voided' ? null : 'First void this entry (undo icon). Only voided entries can be deleted.';

/// Admin-only: marks a purchase/production VOIDED and reverses its stock effect (record is kept).
Widget _voidBtn(BuildContext context, String coll, String id, Rec m) {
  if (m['status'] == 'Voided') return const Icon(Icons.block, color: Colors.red);
  return IconButton(
    tooltip: 'Void entry (reverse stock)',
    icon: const Icon(Icons.undo),
    onPressed: () async {
      final reason = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Void this entry?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The entry stays on record as VOIDED and its stock effect is reversed. Then enter the correct entry again.'),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Void')),
          ],
        ),
      );
      if (ok != true || reason.text.trim().isEmpty) return;
      final b = Db.fs.batch();
      b.update(Db.c(coll).doc(id), {'status': 'Voided', 'voidReason': reason.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
      if (coll == 'purchases') {
        Db.stockMove(b, godownId: '${m['godown']}', item: 'seed', qty: -n(m['netKg']), type: 'void', refType: 'purchase', refId: id, note: reason.text.trim());
      } else if (coll == 'docPurchases') {
        Db.stockMove(b, godownId: '${m['godown']}', item: 'doc', qty: -n(m['netKg']), type: 'void', refType: 'docPurchase', refId: id, note: reason.text.trim());
      } else {
        Db.stockMove(b, godownId: '${m['seedGodown']}', item: 'seed', qty: n(m['seedKg']), type: 'void', refType: 'production', refId: id, note: reason.text.trim());
        Db.tankMove(b, tankId: '${m['tank']}', qty: -n(m['oilKg']), type: 'void', refType: 'production', refId: id, note: reason.text.trim());
        Db.stockMove(b, godownId: '${m['khaliGodown']}', item: 'khali', qty: -n(m['khaliKg']), type: 'void', refType: 'production', refId: id, note: reason.text.trim());
      }
      Db.audit(b, 'void', '$coll $id voided: ${reason.text.trim()}', refId: id);
      try {
        await Db.commit(b);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    },
  );
}

// ------------------------------------------------------------------ Purchase
Future<void> _savePurchase(Rec v, String? id) async {
  final net = n(v['grossKg']) - n(v['tareKg']);
  if (net <= 0) throw Exception('Net weight (gross - tare) must be more than 0');
  final amount = r2(net / 100 * n(v['ratePerQtl']));
  final data = Rec.from(v)..removeWhere((k, _) => k.startsWith('_'));
  final b = Db.fs.batch();
  final ref = Db.c('purchases').doc();
  b.set(ref, {...data, 'netKg': net, 'amount': amount, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email});
  Db.stockMove(b, godownId: '${v['godown']}', item: 'seed', qty: net, type: 'purchase', refType: 'purchase', refId: ref.id,
      note: '${v['supplierName']} slip ${v['slipNo'] ?? ''}');
  Db.audit(b, 'purchase', '${v['supplierName']} ${kg(net)} KG = ${money(amount)}', refId: ref.id);
  await Db.commit(b);
}

Widget purchaseModule(AppState a) => TabsScreen({
      'Seed purchases': CrudScreen(
        title: 'Seed purchase',
        canDelete: a.isAdmin,
        deleteGuard: _needVoid,
        collection: 'purchases',
        orderBy: 'date',
        descending: true,
        canAdd: a.isBiz,
        customSave: _savePurchase,
        fields: [
          const FieldDef('date', 'Date', FT.date),
          const FieldDef('supplier', 'Supplier', FT.doc, coll: 'suppliers'),
          const FieldDef('billNo', 'Supplier bill / invoice no.', FT.text, required: false),
          const FieldDef('godown', 'Seed godown', FT.doc, coll: 'godowns', where: {'type': 'seed'}),
          const FieldDef('vehicleNo', 'Vehicle no.', FT.text, required: false),
          const FieldDef('slipNo', 'Weighment slip no. (external weighbridge)', FT.text, required: false),
          const FieldDef('grossKg', 'Gross weight (KG)', FT.number),
          const FieldDef('tareKg', 'Tare weight (KG)', FT.number),
          const FieldDef('ratePerQtl', 'Rate per Quintal', FT.number),
          const FieldDef('note', 'Note', FT.multiline, required: false),
        ],
        trailing: a.isAdmin ? (c, m, id) => _voidBtn(c, 'purchases', id, m) : null,
        titleOf: (m) => '${_vp(m)}${m['supplierName']} - ${kg(m['netKg'])} KG',
        subtitleOf: (m) => '${m['date']} - ${money(m['amount'])} - slip ${m['slipNo'] ?? '-'}',
      ),
      'DOC purchases (trading)': CrudScreen(
        title: 'DOC purchase',
        canDelete: a.isAdmin,
        deleteGuard: _needVoid,
        trailing: a.isAdmin ? (c, m, id) => _voidBtn(c, 'docPurchases', id, m) : null,
        collection: 'docPurchases',
        orderBy: 'date',
        descending: true,
        canAdd: a.isBiz,
        customSave: _saveDocPurchase,
        fields: const [
          FieldDef('date', 'Date', FT.date),
          FieldDef('supplier', 'Supplier', FT.doc, coll: 'suppliers'),
          FieldDef('billNo', 'Supplier bill no.', FT.text, required: false),
          FieldDef('godown', 'Store in godown', FT.doc, coll: 'godowns'),
          FieldDef('kg', 'Quantity (KG)', FT.number),
          FieldDef('ratePerQtl', 'Rate per Quintal', FT.number),
        ],
        titleOf: (m) => '${_vp(m)}${m['supplierName']} - DOC ${kg(m['netKg'])} KG',
        subtitleOf: (m) => '${m['date']} - ${money(m['amount'])}',
      ),
      'Supplier payments': CrudScreen(
        title: 'Supplier payment',
        canDelete: a.isAdmin,
        canEdit: a.isAdmin,
        collection: 'supplierPayments',
        orderBy: 'date',
        descending: true,
        canAdd: a.isBiz,
        fields: const [
          FieldDef('date', 'Date', FT.date),
          FieldDef('supplier', 'Supplier', FT.doc, coll: 'suppliers'),
          FieldDef('amount', 'Amount paid', FT.number),
          FieldDef('mode', 'Mode', FT.choice, options: payModes),
          FieldDef('reference', 'Reference / cheque / UTR', FT.text, required: false),
        ],
        titleOf: (m) => '${m['supplierName']} - ${money(m['amount'])}',
        subtitleOf: (m) => '${m['date']} - ${m['mode']} ${m['reference'] ?? ''}',
      ),
    });

Future<void> _saveDocPurchase(Rec v, String? id) async {
  final q = n(v['kg']);
  if (q <= 0) throw Exception('Quantity must be more than 0');
  final amount = r2(q / 100 * n(v['ratePerQtl']));
  final data = Rec.from(v)..removeWhere((k, _) => k.startsWith('_'));
  final b = Db.fs.batch();
  final ref = Db.c('docPurchases').doc();
  b.set(ref, {...data, 'netKg': q, 'amount': amount, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email});
  Db.stockMove(b, godownId: '${v['godown']}', item: 'doc', qty: q, type: 'purchase', refType: 'docPurchase', refId: ref.id, note: '${v['supplierName']}');
  Db.audit(b, 'doc-purchase', '${v['supplierName']} ${kg(q)} KG DOC = ${money(amount)}', refId: ref.id);
  await Db.commit(b);
}

// ---------------------------------------------------------------- Production
Future<void> _saveProduction(Rec v, String? id) async {
  final seed = n(v['seedKg']), oil = n(v['oilKg']), khali = n(v['khaliKg']);
  if (seed <= 0) throw Exception('Seed consumed must be more than 0');
  if (oil + khali > seed) throw Exception('Oil + Khali cannot be more than the seed consumed');
  final comp = (await Db.c('settings').doc('company').get()).data() ?? {};
  final dens = n(comp['oilDensity']) > 0 ? n(comp['oilDensity']) : 0.915;
  final tank = (v['_tank'] as Rec?) ?? {};
  if ((n(tank['oilKg']) + oil) / dens > n(tank['capacityL'])) throw Exception('Selected tank would overflow');
  final have = await Db.c('stock').doc('${v['seedGodown']}__seed').get();
  if (n(have.data()?['qtyKg']) < seed) throw Exception('Not enough seed in ${v['seedGodownName']}');
  final data = Rec.from(v)..removeWhere((k, _) => k.startsWith('_'));
  final b = Db.fs.batch();
  final ref = Db.c('productions').doc();
  b.set(ref, {
    ...data,
    'wastageKg': r2(seed - oil - khali),
    'oilYieldPct': r2(oil / seed * 100),
    'khaliYieldPct': r2(khali / seed * 100),
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': Db.email,
  });
  Db.stockMove(b, godownId: '${v['seedGodown']}', item: 'seed', qty: -seed, type: 'production-consume', refType: 'production', refId: ref.id, note: '${v['machineName']}');
  Db.tankMove(b, tankId: '${v['tank']}', qty: oil, type: 'production', refType: 'production', refId: ref.id, note: '${v['machineName']}');
  Db.stockMove(b, godownId: '${v['khaliGodown']}', item: 'khali', qty: khali, type: 'production-output', refType: 'production', refId: ref.id, note: '${v['machineName']}');
  Db.audit(b, 'production', '${v['machineName']} ${v['shift']}: seed ${kg(seed)} -> oil ${kg(oil)} + khali ${kg(khali)} KG', refId: ref.id);
  await Db.commit(b);
}

Widget productionModule(AppState a) => CrudScreen(
      title: 'Production entry',
      canDelete: a.isAdmin,
      deleteGuard: _needVoid,
      collection: 'productions',
      orderBy: 'date',
      descending: true,
      customSave: _saveProduction,
      fields: const [
        FieldDef('date', 'Date', FT.date),
        FieldDef('shift', 'Shift', FT.choice, options: shifts),
        FieldDef('machine', 'Machine', FT.doc, coll: 'machines'),
        FieldDef('seedGodown', 'Seed taken from', FT.doc, coll: 'godowns', where: {'type': 'seed'}),
        FieldDef('seedKg', 'Mustard seed consumed (KG)', FT.number),
        FieldDef('tank', 'Oil stored in tank', FT.doc, coll: 'tanks'),
        FieldDef('oilKg', 'Oil produced (KG)', FT.number),
        FieldDef('khaliGodown', 'Khali stored in', FT.doc, coll: 'godowns', where: {'type': 'khali'}),
        FieldDef('khaliKg', 'Khali produced (KG)', FT.number),
        FieldDef('note', 'Note', FT.multiline, required: false),
      ],
      trailing: a.isAdmin ? (c, m, id) => _voidBtn(c, 'productions', id, m) : null,
      titleOf: (m) => '${_vp(m)}${m['machineName']} - ${m['shift']}',
      subtitleOf: (m) =>
          '${m['date']} - seed ${kg(m['seedKg'])} -> oil ${kg(m['oilKg'])} (${n(m['oilYieldPct']).toStringAsFixed(1)}%) + khali ${kg(m['khaliKg'])} - wastage ${kg(m['wastageKg'])} KG',
    );

// ------------------------------------------------------------------- Quality
Widget qualityModule(AppState a) => CrudScreen(
      title: 'QC record',
      canDelete: a.isAdmin,
      canEdit: a.isAdmin,
      collection: 'qcRecords',
      orderBy: 'date',
      descending: true,
      fields: const [
        FieldDef('date', 'Date', FT.date),
        FieldDef('kind', 'Test type', FT.choice, options: ['Raw material (seed)', 'Mustard oil', 'Production batch']),
        FieldDef('ref', 'Reference (supplier / tank / batch)', FT.text),
        FieldDef('moisturePct', 'Moisture %', FT.number, required: false),
        FieldDef('oilContentPct', 'Oil content % (seed)', FT.number, required: false),
        FieldDef('ffaPct', 'Free fatty acid % (oil)', FT.number, required: false),
        FieldDef('result', 'Result', FT.choice, options: ['Pass', 'Fail / Rejected']),
        FieldDef('remarks', 'Remarks', FT.multiline, required: false),
      ],
      titleOf: (m) => '${m['kind']} - ${m['result']}',
      subtitleOf: (m) => '${m['date']} - ${m['ref']} - moisture ${m['moisturePct']}% FFA ${m['ffaPct']}%',
    );

// ---------------------------------------------------------------- Attendance
/// Saves one record per person per day. The 'employee' login may only ENTER today's attendance (no edits).
Future<void> Function(Rec, String?) _attSaver(AppState a, String coll, String idKey, String nameKey) {
  return (Rec v, String? id) async {
    final docId = '${v['date']}_${v[idKey]}';
    if (a.role == 'employee') {
      if (v['date'] != today()) throw Exception('You can only enter attendance for today.');
      final ex = await Db.c(coll).doc(docId).get();
      if (ex.exists) throw Exception('Attendance for this person is already entered today. Ask your supervisor to correct it.');
    }
    final data = Rec.from(v)..removeWhere((k, _) => k.startsWith('_'));
    final b = Db.fs.batch();
    b.set(Db.c(coll).doc(docId), {...data, 'updatedAt': FieldValue.serverTimestamp(), 'by': Db.email});
    Db.audit(b, 'attendance', '${v[nameKey]} ${v['date']} ${v['status']}', refId: docId);
    await Db.commit(b);
  };
}

Widget attendanceModule(AppState a) => TabsScreen({
      'Staff attendance': CrudScreen(
        title: 'Staff attendance',
        canDelete: a.isAdmin,
        collection: 'attendance',
        orderBy: 'date',
        descending: true,
        canEdit: a.role != 'employee',
        customSave: _attSaver(a, 'attendance', 'employee', 'employeeName'),
        fields: const [
          FieldDef('date', 'Date', FT.date),
          FieldDef('employee', 'Employee', FT.doc, coll: 'attendanceRoster', where: {'type': 'staff'}),
          FieldDef('shift', 'Shift', FT.choice, options: [...shifts, 'General']),
          FieldDef('status', 'Status', FT.choice, options: ['Present', 'Absent', 'Half-day', 'Leave']),
          FieldDef('checkIn', 'Check-in time (HH:mm)', FT.text, required: false),
          FieldDef('checkOut', 'Check-out time (HH:mm)', FT.text, required: false),
          FieldDef('overtimeHrs', 'Overtime hours', FT.number, required: false),
        ],
        titleOf: (m) => '${m['employeeName']} - ${m['status']}',
        subtitleOf: (m) => '${m['date']} - ${m['shift']} - ${m['checkIn'] ?? ''} to ${m['checkOut'] ?? ''} - OT ${m['overtimeHrs'] ?? 0}h',
      ),
      'Labour attendance': CrudScreen(
        title: 'Labour attendance',
        canDelete: a.isAdmin,
        collection: 'labourAttendance',
        orderBy: 'date',
        descending: true,
        canEdit: a.role != 'employee',
        customSave: _attSaver(a, 'labourAttendance', 'labour', 'labourName'),
        fields: const [
          FieldDef('date', 'Date', FT.date),
          FieldDef('labour', 'Labour', FT.doc, coll: 'attendanceRoster', where: {'type': 'labour'}),
          FieldDef('shift', 'Shift', FT.choice, options: [...shifts, 'General']),
          FieldDef('status', 'Status', FT.choice, options: ['Present', 'Half-day', 'Absent']),
          FieldDef('overtimeHrs', 'Overtime hours', FT.number, required: false),
          FieldDef('note', 'Note', FT.text, required: false),
        ],
        titleOf: (m) => '${m['labourName']} - ${m['status']}',
        subtitleOf: (m) => '${m['date']} - ${m['shift']} - OT ${m['overtimeHrs'] ?? 0}h ${m['note'] ?? ''}',
      ),
    });

// ------------------------------------------------------------------ Expenses
Widget expensesModule(AppState a) => CrudScreen(
      title: 'Expense',
      canDelete: a.isAdmin,
      collection: 'expenses',
      orderBy: 'date',
      descending: true,
      canAdd: a.isBiz,
      canEdit: a.isAdmin,
      fields: [
        const FieldDef('date', 'Date', FT.date),
        FieldDef('category', 'Category', FT.choice, options: a.expenseCategories),
        const FieldDef('amount', 'Amount', FT.number),
        const FieldDef('paidTo', 'Paid to', FT.text, required: false),
        const FieldDef('mode', 'Mode', FT.choice, options: payModes),
        const FieldDef('note', 'Note', FT.multiline, required: false),
      ],
      titleOf: (m) => '${m['category']} - ${money(m['amount'])}',
      subtitleOf: (m) => '${m['date']} - ${m['paidTo'] ?? ''} - ${m['mode']}',
    );

// --------------------------------------------------------------------- Users
Future<void> _saveUser(Rec v, String? id) async {
  final role = '${v['role']}', active = v['status'] == 'Active';
  if (id == null) {
    final pw = '${v['password'] ?? ''}';
    if (pw.length < 6) throw Exception('Password must be at least 6 characters');
    try {
      await Db.createStaff('${v['name']}', '${v['email']}'.trim(), pw, role);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? e.code);
    }
    return;
  }
  if (id == Db.uid && (role != 'admin' || !active)) {
    throw Exception('You cannot remove your own admin access');
  }
  final b = Db.fs.batch();
  b.update(Db.c('users').doc(id), {'name': v['name'], 'role': role, 'status': v['status'], 'active': active});
  Db.audit(b, 'update', 'users: ${v['email']} role=$role status=${v['status']}', refId: id);
  await Db.commit(b);
}

Widget usersModule(AppState a) => CrudScreen(
      title: 'User',
      canDelete: a.isAdmin,
      deleteGuard: (id, m) async => id == Db.uid ? 'You cannot delete your own login.' : null,
      collection: 'users',
      orderBy: 'name',
      canEdit: true,
      customSave: _saveUser,
      fields: const [
        FieldDef('name', 'Full name', FT.text),
        FieldDef('email', 'Email (cannot be changed later)', FT.text),
        FieldDef('password', 'Password (only for new users)', FT.text, required: false),
        FieldDef('role', 'Role', FT.choice, options: ['admin', 'manager', 'accountant', 'operator', 'employee', 'driver']),
        FieldDef('status', 'Status', FT.choice, options: ['Active', 'Disabled'], initial: 'Active'),
      ],
      titleOf: (m) => '${m['name']} (${m['role']})',
      subtitleOf: (m) => '${m['email']} - ${m['status']}',
      trailing: (context, m, id) => IconButton(
        tooltip: 'Send password reset email',
        icon: const Icon(Icons.lock_reset),
        onPressed: () async {
          await FirebaseAuth.instance.sendPasswordResetEmail(email: '${m['email']}');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset email sent to ${m['email']}')));
          }
        },
      ),
    );
