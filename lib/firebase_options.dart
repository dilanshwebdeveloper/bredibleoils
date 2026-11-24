// Firebase options for project: b-r-edible-oil-pvt-ltd
// Android, Web and Windows are all configured for the SAME project.
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDdUJCUwb-dOFixlWZi1o4utN1wGZWGI4U',
    appId: '1:803926839029:web:a19d08f726b73a3dd4bfbc',
    messagingSenderId: '803926839029',
    projectId: 'b-r-edible-oil-pvt-ltd',
    authDomain: 'b-r-edible-oil-pvt-ltd.firebaseapp.com',
    storageBucket: 'b-r-edible-oil-pvt-ltd.firebasestorage.app',
    measurementId: 'G-RMX9FJ2VEQ',
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
