import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class SettingsPage extends StatefulWidget {
  final StudyController controller;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  const SettingsPage({
    super.key,
    required this.controller,
    required this.mode,
    required this.onTheme,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final name = TextEditingController(
    text: widget.controller.user?['name'],
  );
  final current = TextEditingController(), password = TextEditingController();
  String? message;
  bool busy = false;
  Future<void> perform(Future<void> Function() task) async {
    setState(() => busy = true);
    try {
      await task();
      if (mounted) setState(() => message = 'Saved.');
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Text(
        'Make yourself at home.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 24),
      StudyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.controller.user?['email'] ?? ''),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await widget.controller.request('PATCH', '/me', {
                        'name': name.text.trim(),
                      });
                      await widget.controller.sync();
                    }),
              child: const Text('Save profile'),
            ),
            const SizedBox(height: 24),
            DropdownMenu<ThemeMode>(
              label: const Text('Appearance'),
              initialSelection: widget.mode,
              onSelected: (v) => widget.onTheme(v!),
              dropdownMenuEntries: const [
                DropdownMenuEntry(
                  value: ThemeMode.system,
                  label: 'Follow system',
                ),
                DropdownMenuEntry(value: ThemeMode.light, label: 'Light'),
                DropdownMenuEntry(value: ThemeMode.dark, label: 'Dark'),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Backend: ${widget.controller.baseUrl}',
              style: const TextStyle(fontSize: 12),
            ),
            const Text(
              'Configure with --dart-define=API_URL=https://your-server',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password · 12+ characters',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await widget.controller.request('POST', '/me/password', {
                        'current': current.text,
                        'password': password.text,
                      });
                      await widget.controller.logout(remote: false);
                    }),
              child: const Text('Change password and revoke all sessions'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      final result = await widget.controller.request(
                        'POST',
                        '/me/recovery',
                        {'password': current.text},
                      );
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text(
                            'Save this recovery code privately',
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'This code replaces any older recovery code. It can reset your password once and expires in one year. It will not be shown again.',
                              ),
                              const SizedBox(height: 20),
                              SelectableText(result['code']),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: result['code']),
                                ),
                                icon: const Icon(Icons.copy_outlined),
                                label: const Text('Copy code'),
                              ),
                            ],
                          ),
                              child: const Text('I saved it'),
                            ),
                          ],
                        ),
                      );
                    }),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Create a one-time recovery code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() => widget.controller.logout()),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 24),
            Text(
              widget.controller.user?['hasPassword'] == false
                  ? 'Account deletion permanently removes your server data and private documents. Sign in again with your provider before confirming deletion.'
                  : 'Account deletion permanently removes your server data and private documents. Enter your current password above to confirm.',
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Permanently delete your account?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Keep account'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete account'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await perform(() async {
                          await widget.controller.request('DELETE', '/me', {
                            'password': current.text,
                            'confirm': 'DELETE',
                          });
                          await widget.controller.logout(
                            remote: false,
                            eraseCache: true,
                          );
                        });
                      }
                    },
              child: const Text('Delete account'),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(message!),
              ),
          ],
        ),
      ),
    ],
  );
  @override
  void dispose() {
    name.dispose();
    current.dispose();
    password.dispose();
    super.dispose();
  }
}
