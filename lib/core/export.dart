import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Saves a text file. Windows: saved in Documents\BR_ERP_Exports. Android/Web: opens the share/save sheet.
/// If that fails, the content is copied to the clipboard instead.
Future<void> saveOrShare(BuildContext context, String name, String content, {String mime = 'text/plain'}) async {
  void toast(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  final bytes = Uint8List.fromList(utf8.encode(content));
  try {
    if (!kIsWeb && Platform.isWindows) {
      final dir = Directory('${Platform.environment['USERPROFILE'] ?? '.'}\\Documents\\BR_ERP_Exports');
      await dir.create(recursive: true);
      final f = File('${dir.path}\\$name');
      await f.writeAsBytes(bytes);
      toast('Saved: ${f.path}');
      return;
    }
    await Share.shareXFiles([XFile.fromData(bytes, name: name, mimeType: mime)], fileNameOverrides: [name]);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: content));
    toast('Could not create a file here - the content was copied to the clipboard instead.');
  }
}
