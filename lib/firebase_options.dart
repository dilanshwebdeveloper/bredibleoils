// Firebase options for project: b-r-edible-oil-pvt-ltd
// ANDROID is ready. For WINDOWS and WEB paste your Web app config below (see README step 4),
// replacing every 'REPLACE_ME'. Until then those two show a "Firebase is not connected" screen.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError('This platform is not supported.');
    }
  }

  // ---- PASTE WEB CONFIG HERE (from Firebase > Project settings > Your apps > Web app) ----
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: '803926839029',
    projectId: 'b-r-edible-oil-pvt-ltd',
    authDomain: 'b-r-edible-oil-pvt-ltd.firebaseapp.com',
    storageBucket: 'b-r-edible-oil-pvt-ltd.firebasestorage.app',
  );

  static const FirebaseOptions windows = web;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAZFJUCok7zTMBPR-DGb1VtfaGINy_LM-o',
    appId: '1:803926839029:android:d3542da2dd374fd9d4bfbc',
    messagingSenderId: '803926839029',
    projectId: 'b-r-edible-oil-pvt-ltd',
    storageBucket: 'b-r-edible-oil-pvt-ltd.firebasestorage.app',
  );
}
