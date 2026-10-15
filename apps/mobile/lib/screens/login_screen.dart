import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../services/auth_service.dart';
import 'shell_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (loading) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      await AuthService.instance.signIn(
        emailController.text.trim(),
        passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ShellScreen()),
      );
    } on AuthException catch (exception) {
      if (mounted) {
        setState(() => error = exception.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Ocorreu um erro inesperado. Verifica a ligação e tenta novamente.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    if (loading || AppConfig.demoMode) return;
    final controller = TextEditingController(text: emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repor palavra-passe'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Indica o email da conta. Receberás uma ligação segura para definir uma nova palavra-passe.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!value.contains('@')) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || !mounted) return;

    setState(() {
      loading = true;
      error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se existir uma conta com esse email, foi enviada a ligação de reposição.',
          ),
        ),
      );
    } on AuthException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível enviar o email de reposição.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = AppConfig.explicitDemoMode;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                children: [
                  const Icon(Icons.shield, size: 80),
                  const SizedBox(height: 12),
                  Text(
                    'BOB MANAGER',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (demo) ...[
                    const SizedBox(height: 12),
                    const Chip(
                      avatar: Icon(Icons.science_outlined),
                      label: Text('MODO DEMONSTRAÇÃO'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: emailController,
                    enabled: !loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: demo ? 'Qualquer email' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !loading,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Palavra-passe',
                      hintText: demo ? 'Qualquer palavra-passe' : null,
                      suffixIcon: IconButton(
                        onPressed: loading
                            ? null
                            : () => setState(
                                  () => obscurePassword = !obscurePassword,
                                ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (!demo)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: loading ? null : _forgotPassword,
                        child: const Text('Esqueci a palavra-passe'),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: loading ? null : submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: loading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
