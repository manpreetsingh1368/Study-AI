import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final StudyController controller;
  const ForgotPasswordScreen({super.key, required this.controller});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final email = TextEditingController(
    text: widget.controller.user?['email'],
  );
  final form = GlobalKey<FormState>();
  bool busy = false, sent = false;
  String? message;
  bool delivery = true;
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final result = await widget.controller.request(
        'POST',
        '/auth/forgot-password',
        {'email': email.text.trim()},
      );
      if (mounted) {
        setState(() {
          sent = true;
          delivery = result['deliveryAvailable'] == true;
          message = delivery ? result['message'] : 'Email recovery isn’t configured on this server. Use your saved recovery code, or ask the server owner to configure SMTP.';
        });
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
      title: const Text('Forgot password'),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: StudyCard(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    alignment: Alignment.centerLeft,
                    child: const CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.lock_reset_rounded, size: 30),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    sent && delivery
                        ? 'Check your inbox.'
                        : 'Let’s get you back in.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the email used for your account. Reset links expire in 20 minutes and work only once.',
                  ),
