import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'notes_editor.dart';
import 'pdf_screen.dart';
import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class SetDetail extends StatefulWidget {
  final Map<String, dynamic> set;
  final StudyController controller;
  const SetDetail({super.key, required this.set, required this.controller});
  @override
  State<SetDetail> createState() => _SetDetailState();
}

class _SetDetailState extends State<SetDetail> {
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
                            'This deletion will synchronize across your devices.',
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
                      : Icons.quiz_outlined,
                  color: accent,
                ),
                title: Text(deck['title']),
                subtitle: deck['kind'] == 'flashcards'
                    ? Text(
                        '${(s['flashcards'] as List).where((q) => q['collection_id'] == deck['id'] && c.isDue(q['id'])).length} cards due',
                      )
                    : Text(
                        '${(s['questions'] as List).where((q) => q['collection_id'] == deck['id']).length} questions',
                      ),
                trailing: Wrap(
                  children: [
                    if (deck['kind'] == 'flashcards')
                      TextButton(
                        onPressed: () => context.go(
                          '/cards/${s['id']}?collection=${Uri.encodeQueryComponent(deck['id'])}&due=true',
                        ),
                        child: const Text('Review due'),
                      ),
                    IconButton(
                      tooltip: 'Open collection',
                      onPressed: () => context.go(
                        '/${deck['kind'] == 'flashcards' ? 'cards' : 'quiz'}/${s['id']}?collection=${Uri.encodeQueryComponent(deck['id'])}',
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
                onTap: () => context.go(
                  '/${deck['kind'] == 'flashcards' ? 'cards' : 'quiz'}/${s['id']}?collection=${Uri.encodeQueryComponent(deck['id'])}',
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        StudyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create a new learning collection',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Gemini uses your notes and PDF. Review generated content for accuracy. Each generation keeps your older collections and results.',
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  DropdownMenu<String>(
                    initialSelection: kind,
                    label: const Text('Create'),
                    onSelected: busy
                        ? null
                        : (v) => setState(() {
                            kind = v!;
                            count = 5;
                          }),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: 'quiz', label: 'Quiz'),
                      const DropdownMenuEntry(
                        value: 'flashcards',
                        label: 'Flashcards',
                      ),
                      DropdownMenuEntry(
                        value: 'exam',
                        label: 'Practice exam · Pro',
                        enabled: pro,
                      ),
                    ],
                  ),
                  DropdownMenu<String>(
                    initialSelection: level,
                    label: const Text('Difficulty'),
                    onSelected: busy ? null : (v) => setState(() => level = v!),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: 'easy', label: 'Easy'),
                      const DropdownMenuEntry(value: 'medium', label: 'Medium'),
                      DropdownMenuEntry(
                        value: 'hard',
                        label: 'Hard · Pro',
                        enabled: pro,
                      ),
                    ],
                  ),
                  DropdownMenu<int>(
                    key: ValueKey(kind),
                    initialSelection: count,
                    label: const Text('Items'),
                    onSelected: busy ? null : (v) => setState(() => count = v!),
                    dropdownMenuEntries: [
                      for (final n in [5, 10, 20, 50])
                        DropdownMenuEntry(
                          value: n,
                          label: '$n',
                          enabled:
                              n <=
                              (kind == 'flashcards'
                                  ? (c.plan['cards'] ?? 5)
                                  : (pro ? 50 : 10)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryActionButton(
                label: busy ? 'Creating with Gemini…' : 'Generate with AI',
                icon: Icons.auto_awesome,
                onPressed: busy || c.offline
                    ? null
                    : () =>
                          action(() => c.generate(s['id'], kind, count, level)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget chat() {
    final conversation = entries
        .where((e) => e['kind'] == 'chat')
        .toList()
        .reversed
        .toList();
    return Column(
      children: [
        panelTitle(
          report == null ? 'Source conversation' : label(report!['kind']),
          Icons.forum_outlined,
          action: report != null
              ? IconButton(
                  tooltip: 'Back to chat',
                  onPressed: () => setState(() => report = null),
                  icon: const Icon(Icons.close, size: 19),
                )
              : null,
        ),
        const Divider(height: 1),
        Expanded(
          child: report != null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: answer(report!, isReport: true),
                )
              : conversation.isEmpty && !busy
              ? emptyChat()
              : ListView(
                  controller: chatScroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    if ((notebook['total'] ?? 0) > entries.length)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => task(
                                () => c.loadEarlierNotebook(widget.set['id']),
                              ),
                        child: const Text('Load earlier responses'),
                      ),
                    for (final raw in conversation) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(left: 32, bottom: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .11),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(5),
                            ),
                          ),
                          child: SelectableText(
                            raw['prompt'],
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      answer(Map<String, dynamic>.from(raw)),
                      const SizedBox(height: 30),
                    ],
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Reading your selected sources…',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (report == null) composerBox(),
      ],
    );
  }

  Widget emptyChat() => SingleChildScrollView(
    padding: const EdgeInsets.all(26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
}
