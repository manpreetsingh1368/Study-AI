import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';
import '../quizzes/study_sessions.dart';
import '../documents/notes_editor.dart';
import '../documents/set_detail.dart';
import '../settings/settings_page.dart';
import '../admin/admin_page.dart';
import '../documents/pdf_screen.dart';
import '../sync/conflicts_screen.dart';

const destinations = [
  ('dashboard', 'Overview', Icons.space_dashboard_outlined),
  ('library', 'My library', Icons.auto_stories_outlined),
  ('cards', 'Flashcards', Icons.style_outlined),
  ('exams', 'Practice exams', Icons.timer_outlined),
  ('conflicts', 'Sync conflicts', Icons.sync_problem_outlined),
  ('analytics', 'Insights', Icons.insights_outlined),
  ('history', 'Study history', Icons.history_rounded),
  ('upgrade', 'Free & Pro', Icons.auto_awesome_outlined),
  ('settings', 'Settings', Icons.tune_rounded),
];

class Workspace extends ConsumerStatefulWidget {
  final String page;
  final String? setId;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  const Workspace({
    super.key,
    required this.page,
    this.setId,
    required this.mode,
    required this.onTheme,
  });
  @override
  ConsumerState<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<Workspace> {
  String search = '';
  String? folder;
  bool collapsed = false;
  StudyController get c => ref.read(studyProvider);
  Future<void> action(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final desktop = MediaQuery.sizeOf(context).width >= 920;
      final title =
          destinations.where((d) => d.$1 == widget.page).firstOrNull?.$2 ??
          'Study notebook';
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              openSearch,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              openSearch,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              context.go('/create'),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              context.go('/create'),
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
              unawaited(c.sync()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: desktop
                ? null
                : AppBar(
                    title: const Text('Study AI'),
                    actions: [
                      if (widget.page == 'set')
                        IconButton(
                          tooltip: c.syncLabel,
                          onPressed: () => unawaited(c.sync()),
                          icon: const Icon(Icons.sync),
                        ),
                      IconButton(
                        onPressed: () => context.go('/create'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
            drawer: desktop ? null : Drawer(child: sidebar()),
            bottomNavigationBar:
                desktop ||
                    widget.page == 'quiz' ||
                    widget.page == 'set' ||
                    (widget.page == 'cards' && widget.setId != null)
                ? null
                : AdaptiveNavigation(page: widget.page),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop && !collapsed) GlassSidebar(child: sidebar()),
                Expanded(
                  child: Column(
                    children: [
                      if (desktop || widget.page != 'set')
                        Row(
                          children: [
                            if (desktop)
                              IconButton(
                                tooltip: 'Toggle sidebar',
                                onPressed: () =>
                                    setState(() => collapsed = !collapsed),
                                icon: const Icon(Icons.menu_open_rounded),
                              ),
                            Expanded(
                              child: ModernToolbar(
                                title: title,
                                onOpenSearch: openSearch,
                                status: c.syncLabel,
                                onSync: () => unawaited(c.sync()),
                                onSearch: (v) => setState(() => search = v),
                              ),
                            ),
                          ],
                        ),
                      if (c.offline || c.error != null || c.attentionCount > 0)
                        Material(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  c.offline
                                      ? Icons.cloud_off_outlined
                                      : Icons.info_outline,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c.error ??
                                        (c.attentionCount > 0
                                            ? '${c.attentionCount} items need attention. Open Sync conflicts to review preserved edits or retry uploads.'
                                            : 'Offline: changes and study progress are saved on this device.'),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(child: body()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget sidebar() =>
      SafeArea(child: SingleChildScrollView(child: _sidebarContents()));
  Widget _sidebarContents() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 27),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Study AI',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.only(left: 48),
          child: Text(
            'MAKE IT CLICK',
            style: TextStyle(fontSize: 9, letterSpacing: 2, color: accent),
          ),
        ),
        const SizedBox(height: 36),
        for (final d in destinations)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selected: widget.page == d.$1,
              selectedTileColor: accent.withValues(alpha: .12),
              leading: Icon(d.$3, size: 21),
              title: Text(d.$2),
              onTap: () => context.go('/${d.$1}'),
            ),
          ),
        if (c.user?['role'] == 'admin')
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Administration'),
            onTap: () => context.go('/admin'),
          ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.plan['name'] ?? 'Free'} workspace',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '${c.plan['used'] ?? 0} / ${c.plan['generations'] ?? 3} AI generations today',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: ((c.plan['used'] ?? 0) / (c.plan['generations'] ?? 3))
                    .clamp(0.0, 1.0),
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 12),
              Text(c.syncLabel, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: CircleAvatar(
            backgroundColor: accent.withValues(alpha: .15),
            child: Text(
              (c.user?['name'] as String? ?? 'S').substring(0, 1).toUpperCase(),
            ),
          ),
          title: Text(
            c.user?['name'] ?? 'Student',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: const Text(
            'Personal workspace',
            style: TextStyle(fontSize: 11),
          ),
          onTap: () => context.go('/settings'),
        ),
      ],
    ),
  );
  Widget body() {
    final set = c.sets.where((s) => s['id'] == widget.setId).firstOrNull;
    if ((widget.page == 'quiz' || widget.page == 'cards') &&
        widget.setId != null) {
      return set == null
          ? const EmptyState(
              title: 'Material unavailable',
              description: 'Refresh your library to download this study set.',
            )
          : StudySession(
              key: ValueKey(
                '${widget.page}${widget.setId}${GoRouterState.of(context).uri.query}',
              ),
              set: set,
              flashcards: widget.page == 'cards',
              controller: c,
              collectionId: GoRouterState.of(context)
                  .uri
                  .queryParameters['collection'],
              dueOnly:
                  GoRouterState.of(context).uri.queryParameters['due'] ==
                  'true',
            );
    }
    if (widget.page == 'conflicts') return ConflictsScreen(controller: c);
    if (widget.page == 'pdf') {
      return set?['document'] == null
          ? const EmptyState(
              title: 'PDF unavailable',
              description: 'Download this material from your library first.',
            )
          : PdfScreen(
              key: ValueKey(set!['document']['id']),
              controller: c,
              document: Map<String, dynamic>.from(set['document']),
              initialPageNumber:
                  (int.tryParse(
                            GoRouterState.of(context)
                                    .uri
                                    .queryParameters['page'] ??
                                '1',
                          ) ??
                          1)
                      .clamp(1, 10000),
            );
    }
    if (widget.page == 'attempt') {
      final attempt = c.attempts
          .where((a) => a['id'] == widget.setId)
          .firstOrNull;
      return attempt == null
          ? const EmptyState(
              title: 'Result unavailable',
              description: 'Synchronize to download this attempt.',
            )
          : AttemptReviewScreen(attempt: attempt);
    }
    if (widget.page == 'create') return NotesEditor(controller: c);
    if (widget.page == 'set') {
      return set == null
          ? const EmptyState(
              title: 'Study set unavailable',
              description: 'It may have been deleted on another device.',
            )
          : SetDetail(key: ValueKey(set['id']), set: set, controller: c);
    }
    if (widget.page == 'settings') {
      return SettingsPage(
        controller: c,
        mode: widget.mode,
        onTheme: widget.onTheme,
      );
    }
    if (widget.page == 'admin') return AdminPage(controller: c);
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 36),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: switch (widget.page) {
            'dashboard' => dashboard(),
            'library' => library(),
            'analytics' => analytics(),
            'history' => history(),
            'cards' => collections('flashcards'),
            'exams' => collections('exam'),
            'upgrade' => upgrade(),
            _ => const EmptyState(
              title: 'Page not found',
              description: 'Choose a page from the navigation.',
            ),
          },
        ),
      ],
    );
  }

  Widget heading(String title, String subtitle, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
        ?trailing,
      ],
    ),
  );
  Widget dashboard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Your next breakthrough\nstarts here.',
        'Welcome back, ${c.user?['name'] ?? 'student'}. Make a little room for learning.',
        trailing: PrimaryActionButton(
          label: 'New notebook',
          onPressed: () => context.go('/create'),
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7660DC), Color(0xFF504799)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LESS READING. MORE UNDERSTANDING.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Give your notes a second life.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Turn a lecture or PDF into a quiz, a flashcard deck,\nor your next lightbulb moment.',
              style: TextStyle(color: Colors.white70, height: 1.6),
            ),
            const SizedBox(height: 22),
            FilledButton.tonalIcon(
              onPressed: () => context.go('/create'),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Create something to learn'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, size) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final stat in [
              (
                'Study sets',
                '${c.analytics['sets'] ?? c.sets.length}',
                Icons.auto_stories_outlined,
              ),
              (
                'Quizzes completed',
                '${c.analytics['completed'] ?? 0}',
                Icons.task_alt,
              ),
              (
                'Average score',
                '${(c.analytics['average'] as num? ?? 0).round()}%',
                Icons.trending_up,
              ),
              (
                'Cards reviewed',
                '${c.analytics['reviewed'] ?? 0}',
                Icons.style_outlined,
              ),
            ])
              SizedBox(
                width:
                    (size.maxWidth - (size.maxWidth < 650 ? 16 : 48)) /
                    (size.maxWidth < 650 ? 2 : 4),
                child: StudyCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(stat.$3, color: accent, size: 21),
                      const SizedBox(height: 18),
                      Text(
                        stat.$2,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(stat.$1, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: Text(
              'Pick up where you left off',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton(
            onPressed: () => context.go('/library'),
            child: const Text('View library'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (c.notebooks.isEmpty)
        StudyCard(
          child: EmptyState(
            title: 'A fresh page, a focused mind',
            description:
                'Save your first notes or PDF to start building your library.',
            action: TextButton(
              onPressed: () => context.go('/create'),
              child: const Text('Create your first study set'),
            ),
          ),
        )
      else
        ...c.notebooks.take(4).map(setTile),
    ],
  );
  Widget setTile(Map<String, dynamic> s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StudyCard(
      padding: const EdgeInsets.all(8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            s['document'] == null
                ? Icons.notes_rounded
                : Icons.picture_as_pdf_outlined,
            color: accent,
          ),
        ),
        title: Text(
          s['title'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${(s['questions'] as List).length} questions · ${(s['flashcards'] as List).length} flashcards',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/set/${s['id']}'),
      ),
    ),
  );
  Widget notebookCard(Map<String, dynamic> set) {
    final books = set['notebook'] as Map? ?? {};
    final date = set['updated_at'] as int?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/set/${set['id']}'),
        child: SizedBox(
          height: 244,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_stories_outlined,
                        color: accent,
                        size: 23,
                      ),
                    ),
                    const Spacer(),
                    if ((set['folder'] ?? '').isNotEmpty)
                      Flexible(
                        child: Text(
                          set['folder'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: accent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  set['title'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    (set['notes'] as String).trim().isEmpty
                        ? 'Explore your PDF with a source-grounded conversation.'
                        : (set['notes'] as String).replaceAll(
                            RegExp(r'\s+'),
                            ' ',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(set['collections'] as List? ?? []).length} collections · ${(books['notes'] as List? ?? []).length} notes',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ],
                ),
                if (date != null)
                  Text(
                    'Updated ${DateTime.fromMillisecondsSinceEpoch(date).toLocal().toString().split(' ').first}',
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget library() {
    final filtered = c.notebooks
        .where((s) => folder == null || (s['folder'] ?? '') == folder)
        .where(
          (s) => '${s['title']} ${s['notes']}'.toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Your library',
          'A home for everything you’re learning.',
          trailing: PrimaryActionButton(
            label: 'New notebook',
            onPressed: () => context.go('/create'),
          ),
        ),
        TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search notebooks, notes, or topics',
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All folders'),
              selected: folder == null,
              onSelected: (_) => setState(() => folder = null),
            ),
            for (final name
                in c.sets
                    .map((s) => s['folder'] as String? ?? '')
                    .toSet()
                    .where((f) => f.isNotEmpty))
              ChoiceChip(
                label: Text(name),
                selected: folder == name,
                onSelected: (_) => setState(() => folder = name),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const EmptyState(
            title: 'No notebooks found',
            description: 'Create a set or try another search.',
          )
        else
          LayoutBuilder(
            builder: (context, size) {
              final columns = size.maxWidth >= 1050
                  ? 3
                  : size.maxWidth >= 650
                  ? 2
                  : 1;
              final width = (size.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final set in filtered)
                    SizedBox(width: width, child: notebookCard(set)),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget analytics() {
    final attempts = c.analytics['attempts'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('See how far you’ve come', 'Every review is a step forward.'),
        StudyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quiz performance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              ProgressChart(
                values: attempts
                    .take(12)
                    .toList()
                    .reversed
                    .map<double>(
                      (a) => (a['score'] as num) / (a['total'] as num) * 100,
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StudyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topics to revisit',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if ((c.analytics['weakTopics'] as List? ?? []).isEmpty)
                const Text(
                  'Your review recommendations will appear after a quiz.',
                ),
              for (final t in c.analytics['weakTopics'] ?? [])
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline, color: accent),
                  title: Text(t['topic']),
                  trailing: Text('${t['mistakes']} missed'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StudyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily study activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if ((c.analytics['daily'] as List? ?? []).isEmpty)
                const Text(
                  'Study activity will appear after your first session.',
                ),
              for (final day in c.analytics['daily'] ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(day['day']),
                  trailing: Text(
                    '${day['sessions']} quizzes · ${day['cards']} reviews',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StudyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topic mastery · Pro',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (c.plan['pro'] != true)
                TextButton(
                  onPressed: () => context.go('/upgrade'),
                  child: const Text('View Pro access'),
                )
              else if ((c.advanced['topics'] as List? ?? []).isEmpty)
                const Text('Complete a quiz to compare your topics.')
              else
                for (final topic in c.advanced['topics'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${topic['topic']} · ${topic['correct']} / ${topic['answers']} correct',
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value:
                              (topic['correct'] as num) /
                              (topic['answers'] as num),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Your learning journal',
        'Real sessions. Small wins. Lasting progress.',
      ),
      if (c.attempts.isEmpty)
        const EmptyState(
          title: 'Your story starts here',
          description: 'Complete a quiz to save your first session.',
        ),
      for (final a in c.attempts.reversed)
        StudyCard(
          padding: const EdgeInsets.all(8),
          child: ListTile(
            onTap: () => context.go('/attempt/${a['id']}'),
            leading: const Icon(Icons.task_alt, color: accent),
            title: Text(a['title'] ?? 'Quiz result'),
            subtitle: Text(
              DateTime.fromMillisecondsSinceEpoch(a['created_at'])
                  .toLocal()
                  .toString()
                  .split('.')
                  .first,
            ),
            trailing: Text('${a['score']} / ${a['total']}'),
          ),
        ),
    ],
  );
  Widget collections(String kind) {
    final decks = [
      for (final s in c.sets)
        for (final d in s['collections'] ?? [])
          if (d['kind'] == kind) {'set': s, 'deck': d},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          kind == 'exam'
              ? 'Practice with purpose.'
              : 'A little review goes a long way.',
          kind == 'exam'
              ? 'Timed exams with server-verified scoring.'
              : 'Your flashcard collections and review schedule.',
        ),
        if (kind == 'exam' && c.plan['pro'] != true)
          StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Practice exams require Pro access.'),
                TextButton(
                  onPressed: () => context.go('/upgrade'),
                  child: const Text('View Free and Pro'),
                ),
              ],
            ),
          ),
        if (decks.isEmpty)
          EmptyState(
            title: 'No collections yet',
            description:
                'Open a study set to generate ${kind == 'exam' ? 'a practice exam' : 'flashcards'}.',
          ),
        for (final entry in decks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StudyCard(
              child: ListTile(
                leading: Icon(
                  kind == 'exam' ? Icons.timer_outlined : Icons.style_outlined,
                  color: accent,
                ),
                title: Text(entry['deck']['title']),
                subtitle: Text(entry['set']['title']),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(
                  '/${kind == 'exam' ? 'quiz' : 'cards'}/${entry['set']['id']}?collection=${Uri.encodeQueryComponent(entry['deck']['id'])}${kind == 'exam' ? '' : '&due=true'}',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> openSearch() async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Search your learning'),
          content: SizedBox(
            width: 560,
            height: 380,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search notes, titles, folders…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => update(() => query = v),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final set in c.sets.where(
                        (s) => '${s['title']} ${s['notes']} ${s['folder']}'
                            .toLowerCase()
                            .contains(query.toLowerCase()),
                      ))
                        ListTile(
                          title: Text(set['title']),
                          onTap: () => Navigator.pop(ctx, set['id']),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) context.go('/set/$selected');
  }

  Widget upgrade() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'More room to grow',
        'Your current plan: ${c.plan['name'] ?? 'Free'}',
      ),
      SubscriptionCard(
        name: 'Free',
        description:
            '${c.catalog['free']?['generations'] ?? 3} AI generations a day\n${c.catalog['free']?['cards'] ?? 5} flashcards per generation\n${c.catalog['free']?['sets'] ?? 5} saved study sets\nQuizzes and basic insights',
      ),
      const SizedBox(height: 20),
      SubscriptionCard(
        name: 'Pro',
        description:
            '${c.catalog['pro']?['generations'] ?? 30} AI generations a day\nUp to ${c.catalog['pro']?['cards'] ?? 50} flashcards per generation\n${c.catalog['pro']?['sets'] ?? 200} saved study sets\nPractice exams and advanced difficulty',
        action: const Text(
          'Pro is activated manually by your administrator.\nPayments are not available in this version.',
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Today: ${c.plan['used'] ?? 0} of ${c.plan['generations'] ?? 3} AI generations used. Limits reset at midnight UTC.',
      ),
    ],
  );
}

class AdaptiveNavigation extends StatelessWidget {
  final String page;
  const AdaptiveNavigation({super.key, required this.page});
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: switch (page) {
      'library' || 'set' || 'quiz' || 'cards' => 1,
      'analytics' || 'history' => 2,
      _ => 0,
    },
    onDestinationSelected: (i) =>
        context.go(['/dashboard', '/library', '/analytics'][i]),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.space_dashboard_outlined),
        label: 'Overview',
      ),
      NavigationDestination(
        icon: Icon(Icons.auto_stories_outlined),
        label: 'Library',
      ),
      NavigationDestination(
        icon: Icon(Icons.insights_outlined),
        label: 'Insights',
      ),
    ],
  );
}
