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
