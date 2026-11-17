import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false;
  String? error;
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await c.authenticate(
        register: register,
        email: email.text.trim(),
        password: password.text,
        name: name.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, size) {
        final desktop = size.maxWidth >= 1000;
        final card = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: StudyCard(
            padding: EdgeInsets.all(desktop ? 36 : 26),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Study AI',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            letterSpacing: -.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    register
                        ? 'Make room for\nyour next idea.'
                        : 'Welcome back.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    register
                        ? 'Create your Study AI workspace.'
                        : 'Welcome back to Study AI.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: desktop ? 188 : 188,
                        child: OutlinedButton.icon(
                          onPressed: !busy && providers['google'] == true
                              ? () => social('google')
                              : null,
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 19,
                            ),
                          ),
                          label: const Text('Google'),
                        ),
                      ),
                      SizedBox(
                        width: desktop ? 188 : 188,
                        child: OutlinedButton.icon(
                          onPressed: !busy && providers['apple'] == true
                              ? () => social('apple')
                              : null,
                          icon: const Icon(Icons.apple, size: 21),
                          label: const Text('Apple'),
                        ),
                      ),
                    ],
                  ),
                  if (providers['google'] != true || providers['apple'] != true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Social sign-in is available when enabled by your server owner.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or use email',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (register) ...[
                    TextFormField(
                      controller: name,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (v) =>
                        !v!.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: obscure,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Password · 12+ characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        v!.length < 12 ? 'Use at least 12 characters' : null,
                    onFieldSubmitted: (_) => busy ? null : submit(),
                  ),
                  if (!register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => context.go('/forgot-password'),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (error != null) ...[
                    ErrorState(message: error!),
                    const SizedBox(height: 16),
                  ],
                  if (c.socialSignInActive)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Finish signing in in your browser.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: c.cancelSocialSignIn,
                            child: const Text('Cancel browser sign-in'),
                          ),
                        ],
                      ),
                    ),
                  PrimaryActionButton(
                    label: busy
                        ? 'Please wait…'
                        : register
                        ? 'Create account'
                        : 'Sign in',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: busy ? null : submit,
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            error = null;
                          }),
                    child: Text(
                      register
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                  if (!register)
                    TextButton(
                      onPressed: busy ? null : () => context.go('/recovery'),
                      child: const Text('Use a recovery code'),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your materials, in your own workspace.\nAI generation requires an internet connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.all(desktop ? 48 : 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (size.maxHeight - (desktop ? 96 : 40)).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Center(
              child: desktop
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 76),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'LESS FRICTION. MORE DISCOVERY.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: accent,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  Text(
                                    'A calm space for\nambitious minds.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(fontSize: 48, height: 1.15),
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    'Bring your sources. Follow your curiosity.\nBuild understanding that lasts.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.9,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 36),
                                  for (final item in [
                                    (
                                      Icons.source_outlined,
                                      'Everything you’re learning, together',
                                    ),
                                    (
                                      Icons.format_quote_rounded,
                                      'Answers connected to your sources',
                                    ),
                                    (
                                      Icons.cloud_done_outlined,
                                      'Your notes, ready across devices',
                                    ),
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 18,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            item.$1,
                                            color: accent,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              item.$2,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          card,
                        ],
                      ),
                    )
                  : card,
            ),
          ),
        );
      },
    ),
  );
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }
}
