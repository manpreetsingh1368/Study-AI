import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'notes_editor.dart';
import 'pdf_screen.dart';
import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class StudyTools extends StatefulWidget {
  final Map<String, dynamic> set;
  final StudyController controller;
  const StudyTools({super.key, required this.set, required this.controller});
  @override
  State<StudyTools> createState() => _StudyToolsState();
}

class _StudyToolsState extends State<StudyTools> {
  String kind = 'quiz', level = 'medium';
  int count = 5;
  bool busy = false, sideBySide = false;
  double split = .5;
  String? error;
  StudyController get c => widget.controller;
  Future<void> action(Future<void> Function() task) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.set;
    final pro = c.plan['pro'] == true;
    final decks = s['collections'] as List? ?? [];
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(s['title'], style: Theme.of(context).textTheme.headlineLarge),
        if ((s['folder'] ?? '').isNotEmpty)
          Text(s['folder'], style: const TextStyle(color: accent)),
        if (s['pending'] == true)
          const Text('Saved on this device · waiting to synchronize'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: MediaQuery.sizeOf(context).height * .85,
                        child: NotesEditor(controller: c, existing: s),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit notes / PDF'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this study set?'),
                          content: const Text(
                            'This removes the notebook, its saved material and conversations from your library on every device.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) {
                        await action(() async {
                          await c.deleteSet(s);
                          if (context.mounted) context.go('/library');
                        });
                      }
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (error != null) ...[
          ErrorState(message: error!),
          const SizedBox(height: 16),
        ],
        if (s['document'] != null) ...[
          StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['document']['filename'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go('/pdf/${s['id']}'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Open PDF'),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => action(() async {
                              await c.documentBytes(s['document']['id']);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'PDF saved for offline reading.',
                                    ),
                                  ),
                                );
                              }
                            }),
                      icon: const Icon(Icons.offline_pin_outlined),
                      label: const Text('Keep offline'),
                    ),
                    if (MediaQuery.sizeOf(context).width > 1000)
                      TextButton(
                        onPressed: () =>
                            setState(() => sideBySide = !sideBySide),
                        child: Text(
                          sideBySide
                              ? 'Close reading panel'
                              : 'Read beside notes',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (sideBySide && s['document'] != null)
          SizedBox(
            height: 540,
            child: LayoutBuilder(
              builder: (context, size) => Row(
                children: [
                  SizedBox(
                    width: (size.maxWidth - 14) * split,
                    child: SingleChildScrollView(
                      child: StudyCard(
                        child: SelectableText(
                          (s['notes'] as String).isEmpty
                              ? 'No notes yet.'
                              : s['notes'],
                        ),
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) => setState(
                        () => split = (split + d.delta.dx / size.maxWidth)
                            .clamp(.25, .75),
                      ),
                      child: const SizedBox(
                        width: 14,
                        height: 540,
                        child: VerticalDivider(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PdfScreen(
                        controller: c,
                        document: Map<String, dynamic>.from(s['document']),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if ((s['notes'] as String).isNotEmpty)
          StudyCard(child: SelectableText(s['notes'])),
        const SizedBox(height: 28),
        Text(
          'Your learning collections',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (decks.isEmpty)
          const Text(
            'Generate a quiz, flashcards, or an exam from this material.',
          ),
        for (final deck in decks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StudyCard(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                leading: Icon(
                  deck['kind'] == 'flashcards'
                      ? Icons.style_outlined
                      : deck['kind'] == 'exam'
                      ? Icons.timer_outlined
