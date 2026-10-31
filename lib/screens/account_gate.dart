import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_couple_store.dart';
import 'couple_home.dart';

class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == null) return const _SignIn();
      return _SharedGate(
        key: ValueKey(snapshot.data!.uid),
        user: snapshot.data!,
        preferences: preferences,
      );
    },
  );
}

class _SignIn extends StatefulWidget {
  const _SignIn();
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _create = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({bool reset = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (reset) {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: _email.text.trim(),
        );
        if (mounted) {
          setState(
            () =>
                _error = 'If that account exists, a reset email will be sent.',
          );
        }
      } else if (_create) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'operation-not-allowed' =>
              'Email sign-in is not enabled in Firebase yet.',
            'email-already-in-use' =>
              'An account already uses this email. Try signing in.',
            'weak-password' =>
              'Choose a stronger password with at least 6 characters.',
            'invalid-email' => 'Enter a valid email address.',
            'network-request-failed' =>
              'Check your internet connection and retry.',
            _ => 'Could not sign in. Check your email and password, or reset your password.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/branding/closer-logo.png', height: 110),
                const SizedBox(height: 24),
                Text(
                  _create ? 'Start your shared space' : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                const Text(
                  'A real account for each of you. Pair once, then keep your conversation and memories together.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!),
                  ),
                FilledButton(
                  onPressed: _busy ? null : () => _submit(),
                  child: Text(
                    _busy
                        ? 'Please wait…'
                        : _create
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _create = !_create;
                          _error = null;
                        }),
                  child: Text(
                    _create
                        ? 'Already have an account? Sign in'
                        : 'Create an account',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _submit(reset: true),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SharedGate extends StatefulWidget {
  const _SharedGate({super.key, required this.user, required this.preferences});
  final User user;
  final SharedPreferences preferences;
  @override
  State<_SharedGate> createState() => _SharedGateState();
}

class _SharedGateState extends State<_SharedGate> with WidgetsBindingObserver {
  late final CloudCoupleStore store;
  final _name = TextEditingController(), _code = TextEditingController();
  String? _invite, _error;
  bool _busy = false, _ready = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store = CloudCoupleStore(widget.preferences, widget.user);
    store.addListener(_change);
    _init();
  }

  Future<void> _init() async {
    await store.start();
    if (mounted) {
      setState(() {
        _name.text = store.yourName;
        _ready = true;
      });
    }
  }

  void _change() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      store.resume();
    } else {
      store.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_change);
    store.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (store.paired) return CoupleHome(store: store);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Closer · Pair with your partner'),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.favorite_outline,
                  size: 54,
                  color: Color(0xFFF18F77),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Two accounts. One shared space.',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text('Signed in as ${widget.user.email}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          store.yourName = _name.text.trim();
                          await store.save();
                          _invite = await store.invite();
                        }),
                  child: const Text('Create partner invitation'),
                ),
                if (_invite != null) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Share this private one-time invitation with your partner. It expires in 24 hours.',
                  ),
                  SelectableText(
                    _invite!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Or enter the invitation your partner sent:'),
                ),
                TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Partner invitation',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          store.yourName = _name.text.trim();
                          await store.save();
                          await store.join(_code.text);
                        }),
                  child: const Text('Pair with partner'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                if (store.storageError != null) Text(store.storageError!),
                TextButton(
                  onPressed: () => store.refresh(),
                  child: const Text('Check connection'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
