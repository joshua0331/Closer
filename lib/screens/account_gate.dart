import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/closer_localizations.dart';
import '../models/cloud_couple_store.dart';
import 'couple_home.dart';
import 'app_loading.dart';

class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const CloserLoadingScreen();
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
  bool _create = false, _busy = false, _showPassword = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_create) {
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
            _ => 'Could not sign in. Check your email and password, then try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF392B27), muted = Color(0xFF806D65);
    const terracotta = Color(0xFFB85842);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/branding/dreamy_peach_gradient_waves.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.white.withValues(alpha: .12)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/branding/closer-logo-transparent.png',
                        height: 76,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) => Text(
                          tr('closer'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            color: terracotta,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE8DE),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                size: 14,
                                color: terracotta,
                              ),
                              SizedBox(width: 7),
                              Text(
                                tr('YOUR SPACE, TOGETHER'),
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: terracotta,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _create ? 'Start your story' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineMedium?.copyWith(
                          color: ink,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        _create
                            ? 'Create your account and make a little more room for us.'
                            : 'Your shared space is right where you left it.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: muted,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0xFFF2E3D9)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1CB85842),
                              blurRadius: 28,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr('EMAIL ADDRESS'),
                              style: textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              style: const TextStyle(color: ink, fontSize: 15),
                              decoration: _fieldDecoration(
                                'you@example.com',
                                Icons.alternate_email_rounded,
                              ),
                            ),
                            const SizedBox(height: 17),
                            Text(
                              tr('PASSWORD'),
                              style: textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _password,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.password],
                              style: const TextStyle(color: ink, fontSize: 15),
                              decoration:
                                  _fieldDecoration(
                                    tr('At least 6 characters'),
                                    Icons.lock_outline_rounded,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword
                                          ? tr('Hide password')
                                          : tr('Show password'),
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: muted,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const _PasswordResetPage(),
                                        ),
                                      ),
                                style: TextButton.styleFrom(
                                  foregroundColor: terracotta,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                ),
                                child: Text(tr('Forgot password?')),
                              ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFB23E36),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            SizedBox(
                              height: 52,
                              child: FilledButton(
                                onPressed: _busy ? null : () => _submit(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: terracotta,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _create
                                                ? 'Create account'
                                                : 'Sign in',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Center(
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _create = !_create;
                                        _error = null;
                                      }),
                                style: TextButton.styleFrom(
                                  foregroundColor: ink,
                                ),
                                child: Text(
                                  _create
                                      ? 'Already have an account?  Sign in'
                                      : 'New to Closer?  Create an account',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFE99B84),
                            size: 14,
                          ),
                          SizedBox(width: 7),
                          Text(
                            tr('A little closer, every day'),
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              letterSpacing: .2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          'By continuing, you agree to Closer’s Terms of Service and Privacy Policy.',
                        ),
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color: muted,
                          height: 1.45,
                          fontSize: 10,
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://closer-court-ddf3a.web.app/terms.html',
                              ),
                            ),
                            style: TextButton.styleFrom(foregroundColor: muted),
                            child: Text(
                              tr('Terms'),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://closer-court-ddf3a.web.app/privacy.html',
                              ),
                            ),
                            style: TextButton.styleFrom(foregroundColor: muted),
                            child: Text(
                              tr('Privacy'),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'mailto:joshuachristianmirang@gmail.com',
                              ),
                            ),
                            style: TextButton.styleFrom(foregroundColor: muted),
                            child: Text(
                              tr('Help'),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB5A49C), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFFB85842), size: 19),
        filled: true,
        fillColor: const Color(0xFFFFFAF6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEADDD4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB85842), width: 1.5),
        ),
      );
}

class _PasswordResetPage extends StatefulWidget {
  const _PasswordResetPage();

  @override
  State<_PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<_PasswordResetPage> {
  final _email = TextEditingController();
  bool _busy = false, _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      setState(
        () => _error = 'Enter the email address for your Closer account.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'invalid-email' => 'Enter a valid email address.',
            'network-request-failed' =>
              'Check your internet connection and try again.',
            _ => 'We couldn’t send the email right now. Check the address and try again.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t send the email right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF392B27), muted = Color(0xFF806D65);
    const terracotta = Color(0xFFB85842);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        title: Text(tr('Reset your password')),
        foregroundColor: ink,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/branding/dreamy_peach_gradient_waves.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.white.withValues(alpha: .12)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .95),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFF2E3D9)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1CB85842),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: _sent
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.mark_email_read_outlined,
                                color: terracotta,
                                size: 54,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                tr('Check your inbox'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'If an account exists for ${_email.text.trim()}, we’ve sent a Closer password reset link.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: muted,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 22),
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(tr('Back to sign in')),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Image.asset(
                                'assets/branding/closer-logo-transparent.png',
                                height: 58,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                tr('Let’s get you back in'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tr(
                                  'Enter your Closer account email and we’ll send you a secure reset link.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: muted, height: 1.5),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                tr('EMAIL ADDRESS'),
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _email,
                                autofocus: true,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                style: const TextStyle(
                                  color: ink,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: tr('you@example.com'),
                                  prefixIcon: Icon(
                                    Icons.alternate_email_rounded,
                                    color: terracotta,
                                  ),
                                  filled: true,
                                  fillColor: Color(0xFFFFFAF6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(14),
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _busy ? null : _send(),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFB23E36),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 52,
                                child: FilledButton(
                                  onPressed: _busy ? null : _send,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: terracotta,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          tr('Send reset link'),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    } else if (defaultTargetPlatform == TargetPlatform.android &&
        store.locations.containsKey(store.uid)) {
      store.resumeBackgroundSharing();
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
      return const CloserLoadingScreen();
    }
    if (store.paired) return CoupleHome(store: store);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Closer · Pair with your partner')),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: tr('Sign out'),
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
                Text(
                  tr('Two accounts. One shared space.'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  trParams('Signed in as {email}', {
                    'email': widget.user.email ?? '',
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 50,
                  decoration: InputDecoration(labelText: tr('Your name')),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          store.yourName = _name.text.trim();
                          await store.save();
                          _invite = await store.invite();
                        }),
                  child: Text(tr('Create partner invitation')),
                ),
                if (_invite != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    tr(
                      'Share this private one-time invitation with your partner. It expires in 24 hours.',
                    ),
                  ),
                  SelectableText(
                    _invite!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(tr('Or enter the invitation your partner sent:')),
                ),
                TextField(
                  controller: _code,
                  decoration: InputDecoration(
                    labelText: tr('Partner invitation'),
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
                  child: Text(tr('Pair with partner')),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                if (store.storageError != null) Text(store.storageError!),
                TextButton(
                  onPressed: () => store.refresh(),
                  child: Text(tr('Check connection')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
