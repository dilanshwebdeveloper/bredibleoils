import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import 'driver_home.dart';
import 'home_shell.dart';

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.user == null) return const LoginScreen();
    if (s.profile == null) return const NoProfileScreen();
    if (!s.profile!.active) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('This account is disabled. Please contact your admin.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: s.signOut, child: const Text('Sign out')),
          ]),
        ),
      );
    }
    if (s.profile!.role == 'driver') return const DriverHome();
    return const HomeShell();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _pass = TextEditingController(), _name = TextEditingController();
  bool _setup = false, _busy = false;
  String? _error, _info;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final auth = FirebaseAuth.instance;
      if (_setup) {
        final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
        await Db.bootstrap(cred.user!, _name.text.trim());
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? e.code;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Type your email first, then tap "Forgot password".');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
      setState(() { _error = null; _info = 'Password reset email sent.'; });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.jpg', height: 160),
                const SizedBox(height: 8),
                Text(_setup ? 'First-time setup: create the Admin account' : 'Sign in',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                if (_setup) ...[
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Admin name')),
                  const SizedBox(height: 12),
                ],
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: _pass, obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password (min 6 characters)'),
                    onSubmitted: (_) => _submit()),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                if (_info != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_info!)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_setup ? 'Create admin & set up' : 'Sign in'),
                  ),
                ),
                if (!_setup) TextButton(onPressed: _reset, child: const Text('Forgot password')),
                TextButton(
                  onPressed: () => setState(() { _setup = !_setup; _error = null; }),
                  child: Text(_setup ? 'Back to sign in' : 'First time? Set up the Admin account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoProfileScreen extends StatefulWidget {
  const NoProfileScreen({super.key});
  @override
  State<NoProfileScreen> createState() => _NoProfileScreenState();
}

class _NoProfileScreenState extends State<NoProfileScreen> {
  String? _msg;
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'This login has no staff profile yet.\n\nIf you are the owner doing the very first setup, tap '
                '"Finish first-time setup". Otherwise ask your Admin to create your profile.',
                textAlign: TextAlign.center,
              ),
              if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() { _busy = true; _msg = null; });
                        try {
                          await Db.bootstrap(s.user!, s.user!.displayName ?? 'Admin');
                        } catch (_) {
                          _msg = 'Setup is already done. Ask your Admin to create your profile.';
                        }
                        if (mounted) setState(() => _busy = false);
                      },
                child: const Text('Finish first-time setup'),
              ),
              TextButton(onPressed: s.signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      ),
    );
  }
}
