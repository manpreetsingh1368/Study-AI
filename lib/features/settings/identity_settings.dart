import 'package:material_ui/material_ui.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class IdentitySettings extends StatefulWidget {
  final StudyController controller;
  const IdentitySettings({super.key, required this.controller});
  @override
  State<IdentitySettings> createState() => _IdentitySettingsState();
}

class _IdentitySettingsState extends State<IdentitySettings> {
  Map<String, dynamic> options = {};
  List<dynamic> identities = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.controller.request('GET', '/me/identities'),
          config = await widget.controller.request('GET', '/auth/options');
      if (mounted) {
        setState(() {
          identities = data['identities'];
          options = Map<String, dynamic>.from(config);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> connect(String provider) async {
    String? password;
    if (widget.controller.user?['hasPassword'] != false) {
      final controller = TextEditingController();
      password = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Connect ${provider == 'google' ? 'Google' : 'Apple'}'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Current Study AI password',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (password == null) return;
    }
    setState(() => busy = true);
    try {
      await widget.controller.socialSignIn(
        provider,
        link: true,
        password: password,
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StudyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connected sign-in methods',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect a provider while signed in. Accounts are never merged automatically just because email addresses match.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 18),
        for (final provider in ['google', 'apple'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              provider == 'apple' ? Icons.apple : Icons.account_circle_outlined,
            ),
            title: Text(provider == 'google' ? 'Google' : 'Apple'),
