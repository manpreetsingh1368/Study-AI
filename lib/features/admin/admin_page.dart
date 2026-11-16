import 'package:material_ui/material_ui.dart';

import 'dart:async';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class AdminPage extends StatefulWidget {
  final StudyController controller;
  const AdminPage({super.key, required this.controller});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<dynamic> users = [];
  Map<String, dynamic> stats = {};
  String? error;
  String query = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final data = await widget.controller.request(
        'GET',
        '/admin/users?search=${Uri.encodeQueryComponent(query)}',
      );
      final s = await widget.controller.request('GET', '/admin/stats');
      if (mounted) {
        setState(() {
          users = data['users'];
          stats = Map<String, dynamic>.from(s);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Text('Administration', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 24),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final metric in [
            ('Students', stats['students'] ?? 0),
            ('Private documents', stats['documents'] ?? 0),
            ('Storage bytes', stats['storage'] ?? 0),
          ])
            StudyCard(
              child: Column(
      const SizedBox(height: 24),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Search students',
          suffixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => query = v,
        onSubmitted: (_) => unawaited(load()),
      ),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: load, child: const Text('Refresh')),
      if (error != null) ErrorState(message: error!),
      Text('$total matching accounts'),
      for (final u in users)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u['name']} · ${u['email']}'),
                Text(
                  '${u['plan']['name']} · ${u['storage']} bytes stored · ${u['plan']['used']} generations today',
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () async {
                        try {
                          final detail = await widget.controller.request(
                            'GET',
                            '/admin/users/${u['id']}',
                          );
                          if (!context.mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(u['email']),
                              content: SizedBox(
                                width: 500,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Role: ${detail['user']['role']}'),
                                      Text(
                                        'Study sets: ${detail['sets']} · Quiz attempts: ${detail['attempts']}',
                                      ),
                                      Text(
                                        'Private storage: ${detail['storage']} bytes',
                                      ),
                                      if (detail['subscription'] != null)
                                        Text(
                                          'Pro: ${DateTime.fromMillisecondsSinceEpoch(detail['subscription']['starts_at'])} to ${DateTime.fromMillisecondsSinceEpoch(detail['subscription']['expires_at'])}',
                                        ),
                                      const SizedBox(height: 16),
                                      for (final usage in detail['usage'])
                                        Text(
                                          '${usage['day']} · ${usage['status']} · ${usage['count']}',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        }
                      },
                      child: const Text('Account details'),
                    ),

                    TextButton(
                      onPressed: () async {
                        final date = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                          initialDateRange: DateTimeRange(
                            start: DateTime.now(),
                            end: DateTime.now().add(const Duration(days: 30)),
                          ),
                        );
                        if (date != null) {
                          try {
                            await widget.controller.request(
                              'PUT',
                              '/admin/users/${u['id']}/pro',
                              {
                                'enabled': true,
                                'startsAt': date.start.millisecondsSinceEpoch,
                                'expiresAt': date.end
                                    .add(const Duration(days: 1))
                                    .millisecondsSinceEpoch,
                              },
                            );
                            await load();
                          } catch (e) {
                            if (mounted) setState(() => error = e.toString());
                          }
                        }
                      },
                      child: const Text('Grant Pro / set expiry'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await widget.controller.request(
                            'PUT',
                            '/admin/users/${u['id']}/pro',
                            {'enabled': false},
                          );
                          await load();
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        }
                      },
                      child: const Text('Revoke Pro'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: OutlinedButton(
            onPressed: loading ? null : () => load(append: true),
            child: Text(loading ? 'Loading…' : 'Load more accounts'),
          ),
        ),
      const SizedBox(height: 28),
      Text('Generation usage', style: Theme.of(context).textTheme.titleLarge),
      for (final u in stats['usage'] ?? [])
        Text('${u['day']} · ${u['status']} · ${u['count']}'),
      const SizedBox(height: 24),
      Text(
        'Administrative audit',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final log in stats['audit'] ?? [])
        Text('${log['action']} · ${log['target_id']}'),
      const SizedBox(height: 24),
      Text('Application errors', style: Theme.of(context).textTheme.titleLarge),
      for (final e in stats['errors'] ?? [])
        Text(
          '${e['code']} · ${DateTime.fromMillisecondsSinceEpoch(e['created_at'])}',
        ),
    ],
  );
}
