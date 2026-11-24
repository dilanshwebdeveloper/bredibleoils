import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/gate.dart';
import 'screens/track_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final opts = DefaultFirebaseOptions.currentPlatform;
  if (opts.apiKey == 'REPLACE_ME') {
    runApp(const SetupNeededApp());
    return;
  }
  await Firebase.initializeApp(options: opts);
  // Public customer tracking link: https://<site>/#/track/<id>  (no login needed)
  final frag = Uri.base.fragment;
  if (kIsWeb && frag.startsWith('/track/')) {
    runApp(TrackApp(id: frag.substring(7).split('?').first));
    return;
  }
  // Offline data entry: Firestore keeps a local cache and syncs when internet returns.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const ErpApp()));
}

class ErpApp extends StatelessWidget {
  const ErpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, s, _) => MaterialApp(
        title: 'B.R. Edible Oils ERP',
        debugShowCheckedModeBanner: false,
        themeMode: s.themeMode,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Gate(),
      ),
    );
  }
}

class SetupNeededApp extends StatelessWidget {
  const SetupNeededApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase is not connected yet.\n\nRun SETUP_WINDOWS.bat or follow README.md, '
              'step "Connect Firebase", then start the app again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
