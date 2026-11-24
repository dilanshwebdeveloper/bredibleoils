import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/fmt.dart';

enum FT { text, multiline, number, date, choice, doc }

class FieldDef {
  final String key, label;
  final FT type;
  final List<String> options;
  final String? coll, labelKey;
  final Map<String, dynamic>? where;
  final bool required;
  final dynamic initial;
  const FieldDef(this.key, this.label, this.type,
      {this.options = const [], this.coll, this.labelKey, this.where, this.required = true, this.initial});
}

/// Generic data-entry page. For FT.doc fields it stores `<key>` (document id),
/// `<key>Name` (label) and `_<key>` (whole document map, for use by custom save code).
class FormPage extends StatefulWidget {
  final String title;
  final List<FieldDef> fields;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> values) onSave;
  const FormPage({super.key, required this.title, required this.fields, required this.onSave, this.initial = const {}});

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _form = GlobalKey<FormState>();
  final Map<String, dynamic> _v = {};
  final Map<String, TextEditingController> _c = {};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _streams = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final init = widget.initial[f.key] ?? f.initial;
      if (f.type == FT.text || f.type == FT.multiline || f.type == FT.number) {
        _c[f.key] = TextEditingController(text: init == null ? '' : '$init');
      } else if (f.type == FT.date) {
        _v[f.key] = init ?? today();
      } else if (init != null) {
        _v[f.key] = init;
        if (f.type == FT.doc) _v['${f.key}Name'] = widget.initial['${f.key}Name'];
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(FieldDef f) {
    return _streams.putIfAbsent(f.key, () {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(f.coll!);
      f.where?.forEach((k, v) => q = q.where(k, isEqualTo: v));
      return q.snapshots();
    });
  }

  String? _req(FieldDef f, String? s) => (f.required && (s == null || s.trim().isEmpty)) ? 'Required' : null;

  Widget _field(FieldDef f) {
    switch (f.type) {
      case FT.text:
      case FT.multiline:
      case FT.number:
        return TextFormField(
          controller: _c[f.key],
          decoration: InputDecoration(labelText: f.label),
          maxLines: f.type == FT.multiline ? 3 : 1,
          keyboardType: f.type == FT.number ? const TextInputType.numberWithOptions(decimal: true) : null,
          validator: (s) {
            final r = _req(f, s);
            if (r != null) return r;
            if (f.type == FT.number && s != null && s.trim().isNotEmpty && double.tryParse(s.trim()) == null) {
              return 'Enter a number';
            }
            return null;
          },
        );
      case FT.date:
        return InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse('${_v[f.key]}') ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _v[f.key] = DateFormat('yyyy-MM-dd').format(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
            child: Text('${_v[f.key] ?? ''}'),
          ),
        );
      case FT.choice:
        return DropdownButtonFormField<String>(
          value: f.options.contains(_v[f.key]) ? _v[f.key] as String : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label),
          items: f.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          validator: (s) => _req(f, s),
          onChanged: (x) => setState(() => _v[f.key] = x),
        );
      case FT.doc:
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream(f),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            final cur = _v[f.key];
            final lk = f.labelKey ?? 'name';
            return DropdownButtonFormField<String>(
              value: docs.any((d) => d.id == cur) ? cur as String : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: f.label),
              items: docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()[lk] ?? d.id}'))).toList(),
              validator: (s) => _req(f, s),
              onChanged: (id) {
                final d = docs.firstWhere((x) => x.id == id);
                setState(() {
                  _v[f.key] = id;
                  _v['${f.key}Name'] = d.data()[lk] ?? d.id;
                  _v['_${f.key}'] = d.data();
                });
              },
            );
          },
        );
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final out = Map<String, dynamic>.from(_v);
    for (final f in widget.fields) {
      if (_c.containsKey(f.key)) {
        final t = _c[f.key]!.text.trim();
        out[f.key] = f.type == FT.number ? (t.isEmpty ? 0.0 : double.parse(t)) : t;
      }
    }
    setState(() => _busy = true);
    try {
      await widget.onSave(out);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
