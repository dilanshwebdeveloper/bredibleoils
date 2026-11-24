import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/fmt.dart';
import '../widgets/form_page.dart';
import 'roles_screen.dart';

Future<String> _diag() async {
  final o = Firebase.app().options;
  final b = StringBuffer('Project: ${o.projectId}\nApp ID: ${o.appId}\nLogin: ${Db.email}\n');
  try {
    final d = await Db.c('users').doc(Db.uid).get(const GetOptions(source: Source.server));
    b.writeln('Database reachable: YES (profile ${d.exists ? 'found' : 'missing'})');
  } catch (e) {
    b.writeln('Database reachable: NO -> $e');
  }
  try {
    final t = await Db.c('tanks').doc('T1').get(const GetOptions(source: Source.server));
    b.writeln('Factory set-up (tanks): ${t.exists ? 'created' : 'NOT created yet'}');
  } catch (e) {
    b.writeln('Tanks check failed -> $e');
  }
  return b.toString();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.c('settings').doc('company').snapshots(),
      builder: (context, s) {
        final m = s.data?.data() ?? {};
        return ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: SwitchListTile(
              title: const Text('Dark theme'),
              value: app.themeMode == ThemeMode.dark,
              onChanged: (_) => app.toggleTheme(),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.business),
              title: Text('${m['companyName'] ?? 'Company profile'}'),
              subtitle: Text('GSTIN ${m['gstin'] ?? '-'}  |  FSSAI ${m['fssai'] ?? '-'}\nInvoice series: ${m['invoicePrefix'] ?? 'BR'}  |  Oil density: ${m['oilDensity'] ?? 0.915} kg/L'),
              isThreeLine: true,
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FormPage(
                    title: 'Company profile',
                    initial: m,
                    fields: const [
                      FieldDef('companyName', 'Company name', FT.text),
                      FieldDef('gstin', 'GSTIN', FT.text),
                      FieldDef('fssai', 'FSSAI licence no.', FT.text),
                      FieldDef('factoryAddress', 'Factory address', FT.multiline),
                      FieldDef('registeredOffice', 'Registered office address', FT.multiline, required: false),
                      FieldDef('state', 'State (for GST place of supply)', FT.choice, options: indianStates),
                      FieldDef('phone', 'Phone', FT.text, required: false),
                      FieldDef('email', 'Email', FT.text, required: false),
                      FieldDef('bankDetails', 'Bank details printed on invoice', FT.multiline, required: false),
                      FieldDef('invoicePrefix', 'Invoice number series prefix', FT.text),
                      FieldDef('oilDensity', 'Mustard oil density (kg per litre)', FT.number),
                      FieldDef('invoiceTerms', 'Terms & conditions on invoice', FT.multiline, required: false),
                      FieldDef('expenseCategories', 'Expense categories (comma separated)', FT.multiline, required: false,
                          initial: 'Electricity, Labour, Transport, Repairs & maintenance, Packing, Fuel, Office, Other'),
                      FieldDef('pfPercent', 'PF % (employee share)', FT.number, initial: 12),
                      FieldDef('pfWageCap', 'PF wage ceiling (Rs.)', FT.number, initial: 15000),
                      FieldDef('esiPercent', 'ESI % (employee share)', FT.number, initial: 0.75),
                      FieldDef('esiWageLimit', 'ESI wage limit (Rs.)', FT.number, initial: 21000),
                      FieldDef('trackingBaseUrl', 'Website address for customer tracking links', FT.text, initial: 'https://br-industriestonk.web.app'),
                    ],
                    onSave: (v) async {
                      if (n(v['oilDensity']) <= 0) throw Exception('Density must be more than 0');
                      final data = Map<String, dynamic>.from(v)..removeWhere((k, _) => k.startsWith('_'));
                      final b = Db.fs.batch();
                      b.set(Db.c('settings').doc('company'), data, SetOptions(merge: true));
                      Db.audit(b, 'update', 'Company settings changed');
                      await Db.commit(b);
                    },
                  ),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: const Text('Check database connection'),
              subtitle: const Text('Shows which Firebase project this app uses and whether it can reach the database'),
              onTap: () => showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Connection check'),
                  content: FutureBuilder<String>(
                    future: _diag(),
                    builder: (c, s) => SingleChildScrollView(child: SelectableText(s.data ?? 'Checking...')),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Role permissions'),
              subtitle: const Text('Choose which screens manager / accountant / operator can open'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RolesScreen())),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.image_outlined),
              title: Text('Company logo'),
              subtitle: Text('To replace the logo, replace the file assets/logo.jpg in the project and rebuild the app.'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Government integrations'),
              subtitle: Text('E-invoice (IRN), e-way bill and TallyPrime export are NOT active in this version.'),
            ),
          ),
        ]);
      },
    );
  }
}
