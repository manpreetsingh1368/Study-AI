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
      await ref
          .read(studyProvider)
          .authenticate(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: StudyCard(
            padding: const EdgeInsets.all(36),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: accent,
                    size: 42,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'A little focus.\nA lot of possibility.',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    register
                        ? 'Create your Study AI workspace.'
                        : 'Welcome back to Study AI.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  if (register) ...[
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Your name'),
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
                    ),
                    validator: (v) =>
                        !v!.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Password · 12+ characters',
                    ),
                    validator: (v) =>
                        v!.length < 12 ? 'Use at least 12 characters' : null,
                    onFieldSubmitted: (_) => busy ? null : submit(),
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    ErrorState(message: error!),
                    const SizedBox(height: 16),
                  ],
                  PrimaryActionButton(
                    label: busy
                        ? 'Please wait…'
                        : register
                        ? 'Create account'
                        : 'Sign in',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: busy ? null : submit,
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 12),
                  const Text(
                    'Your materials, in your own workspace.\nAI generation requires an internet connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
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
