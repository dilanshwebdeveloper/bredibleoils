import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'fmt.dart';

class Db {
  static FirebaseFirestore get fs => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> c(String name) => fs.collection(name);
  static String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  static String get email => FirebaseAuth.instance.currentUser?.email ?? '';

  /// Append an audit-trail entry to a WriteBatch or Transaction.
  static void audit(dynamic w, String action, String detail, {String? refId}) {
    w.set(c('auditLogs').doc(), {
      'at': FieldValue.serverTimestamp(),
      'uid': uid,
      'email': email,
      'action': action,
      'detail': detail,
      'ref': refId,
    });
  }

  /// Commit a batch. When offline the write is queued locally and synced later,
  /// so we do not wait forever for the server.
  static Future<void> commit(WriteBatch b) async {
    try {
      await b.commit().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // queued offline - will sync automatically
    }
  }

  /// qty is signed: + stock in, - stock out. Works with WriteBatch or Transaction.
  static void stockMove(dynamic w,
      {required String godownId, required String item, required double qty, required String type,
      required String refType, String? refId, String note = ''}) {
    w.set(
      c('stock').doc('${godownId}__$item'),
      {'godownId': godownId, 'item': item, 'qtyKg': FieldValue.increment(qty), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    w.set(c('stockLedger').doc(), {
      'godownId': godownId, 'item': item, 'qtyKg': qty, 'type': type, 'refType': refType, 'refId': refId,
      'note': note, 'day': today(), 'at': FieldValue.serverTimestamp(), 'by': email,
    });
  }

  static void tankMove(dynamic w,
      {required String tankId, required double qty, required String type, required String refType,
      String? refId, String note = ''}) {
    w.update(c('tanks').doc(tankId), {'oilKg': FieldValue.increment(qty), 'updatedAt': FieldValue.serverTimestamp()});
    w.set(c('tankLedger').doc(), {
      'tankId': tankId, 'qtyKg': qty, 'type': type, 'refType': refType, 'refId': refId,
      'note': note, 'day': today(), 'at': FieldValue.serverTimestamp(), 'by': email,
    });
  }

  /// First-ever admin. Allowed once (Firestore rules lock it after meta/bootstrap exists).
  static Future<void> bootstrap(User u, String name) async {
    final b = fs.batch();
    b.set(c('meta').doc('bootstrap'), {'by': u.uid, 'at': FieldValue.serverTimestamp()});
    b.set(c('users').doc(u.uid), {
      'name': name.isEmpty ? 'Admin' : name, 'email': u.email, 'role': 'admin',
      'status': 'Active', 'active': true, 'createdAt': FieldValue.serverTimestamp(),
    });
    await b.commit();
    final b2 = fs.batch();
    b2.set(c('settings').doc('company'), {
      'companyName': 'B.R. Edible Oils Pvt. Ltd.',
      'gstin': '08AAECB3374K1ZH',
      'fssai': '12221999000180',
      'factoryAddress': 'F-2 & 3, RIICO Industrial Area, Tonk, Rajasthan - 304001, India',
      'registeredOffice': '',
      'state': '08 - Rajasthan',
      'phone': '', 'email': '', 'bankDetails': '',
      'invoiceTerms': 'Goods once sold will not be taken back. Subject to Tonk jurisdiction.',
      'invoicePrefix': 'BR',
      'oilDensity': 0.915,
    });
    audit(b2, 'setup', 'First admin created');
    await b2.commit();
  }

  /// Creates the 10 machines, 5+1 godowns and 7 tanks (needs internet).
  /// Written in small batches. Returns an error message, or null when done / already done.
  static Future<String?> seedFactory() async {
    try {
      final t1 = await c('tanks').doc('T1').get(const GetOptions(source: Source.server));
      if (t1.exists) return null;
      final b1 = fs.batch();
      for (var i = 1; i <= 10; i++) {
        b1.set(c('machines').doc('M$i'), {'name': 'Machine $i', 'code': 'M$i', 'status': 'Active', 'order': i});
      }
      await b1.commit();
      final b2 = fs.batch();
      for (var i = 1; i <= 5; i++) {
        b2.set(c('godowns').doc('SG$i'), {'name': 'Seed Godown $i', 'type': 'seed', 'order': i});
      }
      b2.set(c('godowns').doc('KG1'), {'name': 'Khali Godown', 'type': 'khali', 'order': 6});
      await b2.commit();
      final b3 = fs.batch();
      for (var i = 1; i <= 7; i++) {
        b3.set(c('tanks').doc('T$i'), {'name': 'Tank $i', 'capacityL': 25000, 'oilKg': 0, 'order': i});
      }
      await b3.commit();
      final b4 = fs.batch();
      audit(b4, 'setup', 'Default factory set-up created: 10 machines, 6 godowns, 7 tanks');
      await b4.commit();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> seedIfEmpty() async {
    await seedFactory();
  }

  /// Admin creates a staff login without being signed out (uses a second Firebase app instance).
  static Future<void> createStaff(String name, String email, String password, String role) async {
    FirebaseApp app;
    try {
      app = Firebase.app('secondary');
    } catch (_) {
      app = await Firebase.initializeApp(name: 'secondary', options: Firebase.app().options);
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
    final b = fs.batch();
    b.set(c('users').doc(cred.user!.uid), {
      'name': name, 'email': email, 'role': role, 'status': 'Active', 'active': true,
      'createdAt': FieldValue.serverTimestamp(), 'createdBy': Db.email,
    });
    audit(b, 'create', 'users: $email ($role)');
    await b.commit();
    await auth.signOut();
  }
}
