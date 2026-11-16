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
      children: [
        const SizedBox(height: 30),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: accent,
            size: 29,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Meet your material.',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 12),
        Text(
          'Ask a question. Find a connection.\nFollow the evidence back to your sources.',
          style: TextStyle(
            height: 1.8,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        for (final prompt in [
          'What are the most important ideas?',
          'Explain the main concepts in plain language.',
          'What connections exist between these sources?',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () {
                composer.text = prompt;
                composerFocus.requestFocus();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(prompt, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.north_west_rounded, size: 16),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget composerBox() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .25)),
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.enter,
                control: true,
              ): () =>
                  ask('chat', composer.text),
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                  ask('chat', composer.text),
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: composer,
                    focusNode: composerFocus,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Ask your sources…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send question · Ctrl/Command+Enter',
                  onPressed: busy || c.offline || validSelection.isEmpty
                      ? null
                      : () => ask('chat', composer.text),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          c.offline
              ? 'Offline · saved conversations remain available'
              : '${validSelection.length} ${validSelection.length == 1 ? 'source' : 'sources'} selected · 1 AI credit per request · verify important claims',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
  Widget answer(Map<String, dynamic> entry, {bool isReport = false}) {
    final content = entry['content'];
    final blocks = content['blocks'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            const Text(
              'STUDY AI',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
            const Spacer(),
            if (blocks.isNotEmpty)
              IconButton(
                tooltip: 'Save answer to Studio notes',
                onPressed: busy ? null : () => pin(entry),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              ),
            if (blocks.isNotEmpty)
              IconButton(
                tooltip: 'Copy answer',
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: blocks
                        .map((b) => '${b['heading']}\n${b['text']}')
                        .join('\n\n'),
                  ),
                ),
                icon: const Icon(Icons.copy_outlined, size: 16),
              ),
            if (isReport)
              IconButton(
                tooltip: 'Export Markdown',
                onPressed: () => export(
                  label(entry['kind']),
                  blocks
                      .map(
                        (b) =>
                            '## ${b['heading']}\n\n${b['text']}\n\n${(b['citations'] as List).map((v) => '> ${v['quote']} — ${v['title']}${v['page'] == null ? '' : ' (page ${v['page']})'}').join('\n\n')}',
                      )
                      .join('\n\n'),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (content['insufficientEvidence'] == true)
          const Text(
            'I couldn’t find enough evidence in the selected sources to answer this. Try a more specific question or add another source.',
            style: TextStyle(height: 1.8),
          ),
        for (final block in blocks) ...[
          if ((block['heading'] as String).isNotEmpty) ...[
            Text(
              block['heading'],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(
            block['text'],
            style: const TextStyle(fontSize: 13, height: 1.85),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < (block['citations'] as List).length; i++)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(
                    Icons.format_quote,
                    size: 12,
                    color: accent,
                  ),
                  label: Text(
                    '${i + 1} · ${block['citations'][i]['page'] == null ? 'Notes' : 'p. ${block['citations'][i]['page']}'}',
                    style: const TextStyle(fontSize: 10, color: accent),
                  ),
                  onPressed: () => citation(
                    Map<String, dynamic>.from(block['citations'][i]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        if ((content['followUps'] as List).isNotEmpty) ...[
          Text(
            'Keep exploring',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final follow in content['followUps'])
            TextButton(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
              ),
              onPressed: () {
                setState(() => report = null);
                composer.text = follow;
                composerFocus.requestFocus();
              },
              child: Text(follow, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ],
    );
  }

  Widget studio() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panelTitle('Studio', Icons.auto_awesome_outlined),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Turn sources into understanding',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final item in [
              (
                'summary',
                'Source overview',
                'The essentials, connected',
                Icons.subject_rounded,
              ),
              (
                'guide',
                'Study guide',
                'Concepts and review priorities',
                Icons.menu_book_outlined,
              ),
              (
                'faq',
                'FAQ',
                'Questions worth asking',
                Icons.question_answer_outlined,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: accent.withValues(alpha: .045),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: busy || c.offline || validSelection.isEmpty
                        ? null
                        : () => ask(
                            item.$1,
                            'Create a ${item.$2.toLowerCase()} using only the selected sources.',
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(item.$4, color: accent, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.$3,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.add, size: 16, color: accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'Each Studio generation uses 1 AI credit.',
              style: TextStyle(fontSize: 9),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your learning collections',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Create quizzes, cards or exams',
                  onPressed: showTools,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
}
