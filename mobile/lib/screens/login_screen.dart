import 'package:flutter/material.dart';
import '../api/api_client.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _password2Error;

  bool _validate() {
    final email = _email.text.trim().toLowerCase();
    setState(() {
      _emailError = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
          ? null
          : 'Podaj poprawny adres e-mail';
      _passwordError = _password.text.length >= 8
          ? null
          : 'Hasło musi mieć co najmniej 8 znaków';
      _password2Error = !_registerMode || _password2.text == _password.text
          ? null
          : 'Hasła różnią się od siebie';
    });
    return _emailError == null &&
        _passwordError == null &&
        _password2Error == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final email = _email.text.trim().toLowerCase();

    setState(() => _busy = true);
    try {
      if (_registerMode) {
        await ApiClient.instance.register(email, _password.text);
      } else {
        await ApiClient.instance.login(email, _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _emailError = null;
      _passwordError = null;
      _password2Error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.share_location,
                    size: 56, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              Text('InCircle',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                _registerMode
                    ? 'Utwórz nowe konto'
                    : 'Zaloguj się do swojego konta',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: const Icon(Icons.mail_outline),
                  errorText: _emailError,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Hasło',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _passwordError,
                ),
                onSubmitted: _registerMode ? null : (_) => _submit(),
              ),
              if (_registerMode) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _password2,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Powtórz hasło',
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: _password2Error,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: scheme.onPrimary))
                    : Text(_registerMode ? 'Utwórz konto' : 'Zaloguj się'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_registerMode ? 'Masz już konto?' : 'Nie masz konta?'),
                  TextButton(
                    onPressed: _toggleMode,
                    child: Text(
                        _registerMode ? 'Zaloguj się' : 'Zarejestruj się'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
