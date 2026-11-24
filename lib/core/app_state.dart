import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Profile {
  final String uid, name, email, role;
  final bool active;
  Profile(this.uid, this.name, this.email, this.role, this.active);
  factory Profile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Profile(d.id, '${m['name'] ?? ''}', '${m['email'] ?? ''}', '${m['role'] ?? 'operator'}', m['active'] == true);
  }
}

/// Modules the admin can switch on/off per role (Settings > Role permissions).
const configurable = ['dashboard', 'purchase', 'production', 'inventory', 'tanks', 'quality', 'sales', 'shipments',
  'attendance', 'expenses', 'masters', 'audit', 'reports', 'payroll'];
const adminOnly = ['users', 'settings', 'backup', 'import'];
const _all = [...configurable, ...adminOnly];

const roleModules = <String, List<String>>{
  'admin': _all,
  'manager': configurable,
  'accountant': ['dashboard', 'purchase', 'inventory', 'sales', 'shipments', 'expenses', 'masters', 'reports'],
  'operator': ['dashboard', 'production', 'inventory', 'tanks', 'quality', 'attendance'],
};
const internalRoles = ['admin', 'manager', 'accountant', 'operator'];
const allRoles = ['admin', 'manager', 'accountant', 'operator', 'employee', 'driver'];

class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;
  Profile? profile;
  User? user;
  bool loading = true;
  Map<String, dynamic> company = {};
  Map<String, List<String>> perms = {};
  StreamSubscription? _a, _p, _s;

  AppState() {
    _a = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
  }

  void _onAuth(User? u) {
    user = u;
    _p?.cancel();
    _s?.cancel();
    profile = null;
    if (u == null) {
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    _p = FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots().listen((d) {
      profile = d.exists ? Profile.fromDoc(d) : null;
      loading = false;
      _watchSettings();
      notifyListeners();
    }, onError: (_) {
      loading = false;
      notifyListeners();
    });
  }

  void _watchSettings() {
    _s?.cancel();
    _s = null;
    final p = profile;
    if (p == null || !p.active || !internalRoles.contains(p.role)) return;
    _s = FirebaseFirestore.instance.collection('settings').snapshots().listen((q) {
      for (final d in q.docs) {
        if (d.id == 'company') company = d.data();
        if (d.id == 'permissions') {
          perms = d.data().map((k, v) => MapEntry(k, List<String>.from(v as List)));
        }
      }
      notifyListeners();
    }, onError: (_) {});
  }

  String get role => profile?.role ?? '';
  bool get isAdmin => role == 'admin';
  bool get isMgr => role == 'admin' || role == 'manager';
  bool get isBiz => isMgr || role == 'accountant';

  bool can(String module) {
    final p = profile;
    if (p == null || !p.active) return false;
    if (p.role == 'admin') return _all.contains(module);
    if (p.role == 'employee') return module == 'attendance'; // fixed: attendance entry only
    if (p.role == 'driver') return false;
    if (adminOnly.contains(module)) return false;
    return (perms[p.role] ?? roleModules[p.role] ?? const <String>[]).contains(module);
  }

  List<String> get expenseCategories {
    final s = '${company['expenseCategories'] ?? ''}';
    final l = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return l.isEmpty
        ? ['Electricity', 'Labour', 'Transport', 'Repairs & maintenance', 'Packing', 'Fuel', 'Office', 'Other']
        : l;
  }

  String get trackingBase {
    final s = '${company['trackingBaseUrl'] ?? ''}'.trim();
    return (s.isEmpty ? 'https://br-industriestonk.web.app' : s).replaceAll(RegExp(r'/+$'), '');
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  @override
  void dispose() {
    _a?.cancel();
    _p?.cancel();
    _s?.cancel();
    super.dispose();
  }
}
