import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class ConflictsScreen extends StatelessWidget {
  final StudyController controller;
  const ConflictsScreen({super.key, required this.controller});
  Future<void> resolve(
    BuildContext context,
    Map<String, dynamic> conflict,
    String choice,
  ) async {
    try {
      await controller.resolveConflict(conflict, resolution: choice);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          'Keep the ideas. Resolve the edits.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your local copy is preserved here. Compare it with the current server copy before choosing what to keep.',
        ),
        const SizedBox(height: 24),
        if (controller.attentionCount == 0)
          const EmptyState(
            title: 'Everything is in harmony',
            description: 'There are no conflicting edits to resolve.',
          ),
        for (final op in controller.failedOperations)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StudyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Study progress could not synchronize',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(op['message']),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () => controller.retryFailedOperation(op),
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: () =>
                            controller.discardFailedOperation(op['id']),
                        child: const Text('Discard rejected operation'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final issue in controller.uploadIssues)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StudyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue['name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(issue['message']),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () async {
                          try {
                            await controller.retryUpload(issue['id']);
                          } catch (e) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                          }
                        },
                        child: const Text('Retry against current version'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            final bytes = await controller.pendingPdf(
                              issue['id'],
                            );
                            await FilePicker.saveFile(
                              fileName: issue['name'],
                              bytes: bytes,
                              type: FileType.custom,
                              allowedExtensions: ['pdf'],
                            );
                          } catch (e) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                        child: const Text('Save local PDF to disk'),
                      ),
                      TextButton(
                        onPressed: () => controller.discardUpload(issue['id']),
                        child: const Text('Discard upload'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final conflict in controller.conflicts)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: StudyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conflict['local']['title'] ?? 'Deleted study set',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(conflict['message']),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, size) {
                      final remote = controller.sets
                          .where((s) => s['id'] == conflict['local']['setId'])
                          .firstOrNull;
                      final local = conflict['local'];
                      final children = [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YOUR LOCAL EDIT',
                                style: TextStyle(color: accent, fontSize: 11),
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                local['kind'] == 'delete'
                                    ? 'You requested deletion.'
                                    : local['notes'] ?? '',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT SERVER COPY',
                                style: TextStyle(color: accent, fontSize: 11),
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                remote?['notes'] ?? 'Deleted or unavailable.',
                              ),
                            ],
                          ),
                        ),
                      ];
                      return size.maxWidth > 650
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: children,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your edit: ${local['notes'] ?? 'Delete requested'}',
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Server: ${remote?['notes'] ?? 'Deleted or unavailable'}',
                                ),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () => resolve(context, conflict, 'copy'),
                        child: const Text('Save local notes as a new set'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final remote = controller.sets
                              .where(
                                (s) => s['id'] == conflict['local']['setId'],
                              )
                              .firstOrNull;
                          if (remote == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Server copy was deleted. Save a separate copy instead.',
                                ),
                              ),
                            );
                            return;
                          }
                          final title = TextEditingController(
                            text: conflict['local']['title'],
                          );
                          final notes = TextEditingController(
                            text: conflict['local']['notes'],
                          );
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Merge your notes'),
                              content: SizedBox(
                                width: 600,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: title,
                                        decoration: const InputDecoration(
                                          labelText: 'Title',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: notes,
                                        maxLines: 12,
                                        decoration: const InputDecoration(
                                          labelText: 'Notes to save over the displayed server version',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Save merged version'),
                                ),
                              ],
                            ),
                          );
                          if (accepted == true) {
                            try {
                              await controller.resolveConflict(
                                conflict,
                                resolution: 'merge',
                                title: title.text,
                                notes: notes.text,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          }
                          title.dispose();
                          notes.dispose();
                        },
                        child: const Text('Merge manually'),
                      ),
                      TextButton(
                        onPressed: () => resolve(context, conflict, 'discard'),
                        child: const Text('Keep server copy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
