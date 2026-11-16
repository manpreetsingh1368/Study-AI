import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class RecoveryScreen extends StatefulWidget {
  final StudyController controller;
  const RecoveryScreen({super.key, required this.controller});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final email = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController();
  bool busy = false;
  String? message;
  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.controller.request('POST', '/auth/recover', {
        'email': email.text.trim(),
        'code': code.text.trim(),
        'password': password.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password replaced. Sign in with your new password.'),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('Account recovery'),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.key_outlined, color: accent, size: 40),
                const SizedBox(height: 20),
                Text(
                  'Use your recovery code',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter the private code you saved from Settings. No recovery email is sent. A successful reset consumes the code and signs out every device.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Account email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Recovery code'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password · 12+ characters',
                  ),
                ),
                const SizedBox(height: 20),
                if (message != null) ...[
                  ErrorState(message: message!),
                  const SizedBox(height: 16),
                ],
                PrimaryActionButton(
                  label: busy ? 'Recovering…' : 'Replace password',
                  icon: Icons.key,
                  onPressed: busy ? null : submit,
                ),
              ],
            ),
          ),
        ),
      ),
