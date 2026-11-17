import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';
import 'notes_editor.dart';
import 'pdf_screen.dart';
import 'study_tools.dart';

class SetDetail extends StatefulWidget {
  final Map<String, dynamic> set;
  final StudyController controller;
  const SetDetail({super.key, required this.set, required this.controller});
  @override
  State<SetDetail> createState() => _SetDetailState();
}

class _SetDetailState extends State<SetDetail> {
  final composer = TextEditingController(),
      sourceSearch = TextEditingController();
  final composerFocus = FocusNode();
  final chatScroll = ScrollController();
  late Set<String> selected;
  String? error;
  bool busy = false;
  int mobileTab = 1;
  Map<String, dynamic>? report;
  StudyController get c => widget.controller;
  Map<String, dynamic> get notebook =>
      Map<String, dynamic>.from(widget.set['notebook'] ?? {});
  List<dynamic> get entries => notebook['entries'] as List? ?? [];
  List<dynamic> get savedNotes => notebook['notes'] as List? ?? [];
  List<String> get validSelection =>
      selected.where((id) => c.sets.any((s) => s['id'] == id)).toList();
  @override
  void initState() {
    super.initState();
    selected = Set<String>.from(notebook['sourceIds'] ?? [widget.set['id']]);
  }

  Future<void> task(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> ask(String kind, String prompt) async {
    if (prompt.trim().isEmpty) return;
    await task(() async {
      final result = await c.askNotebook(
        widget.set['id'],
        kind,
        prompt.trim(),
        validSelection,
      );
      if (!mounted) return;
      setState(() {
        report = kind == 'chat' ? null : result;
        composer.clear();
        mobileTab = 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (chatScroll.hasClients) {
          chatScroll.animateTo(
            chatScroll.position.maxScrollExtent,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void showTools() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: ListenableBuilder(
        listenable: c,
        builder: (_, _) => StudyTools(
          set:
              c.sets.where((s) => s['id'] == widget.set['id']).firstOrNull ??
              widget.set,
          controller: c,
        ),
      ),
    ),
  );
  void editSource() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: NotesEditor(controller: c, existing: widget.set),
    ),
  );
  Future<void> addSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.notes_rounded),
                title: const Text('Paste text'),
                subtitle: const Text(
                  'A lecture, reading excerpt, or your own notes',
                ),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Upload a PDF'),
                subtitle: const Text(
                  'Private storage with selectable source text',
                ),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (validSelection.length >= 8) {
      setState(
        () => error = 'Select up to 8 sources at a time. Uncheck one before adding another.',
      );
      return;
    }
    if (choice == 'pdf') {
      await task(() async {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (file == null) return;
        if ((await file.length() ?? 10485761) > 10485760) {
          throw ApiException(413, 'Choose a PDF smaller than 10 MB.');
        }
        final source = await c.saveSet(
          file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''),
          '',
          folder: widget.set['folder'] ?? '',
        );
        await c.upload(source['id'], file.name, await file.readAsBytes());
        if (mounted) setState(() => selected.add(source['id']));
      });
      return;
    }
    final title = TextEditingController(), text = TextEditingController();
    final value = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a text source'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Source title'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: text,
                  minLines: 7,
                  maxLines: 12,
                  maxLength: 100000,
                  decoration: const InputDecoration(
                    labelText: 'Paste your source text',
                    alignLabelWithHint: true,
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
            child: const Text('Add source'),
          ),
        ],
      ),
    );
    if (value == true && mounted) {
      await task(() async {
        if (title.text.trim().isEmpty || text.text.trim().isEmpty) {
          throw ApiException(400, 'Give this source a title and some text.');
        }
        final source = await c.saveSet(
          title.text.trim(),
          text.text.trim(),
          folder: widget.set['folder'] ?? '',
        );
        if (mounted) setState(() => selected.add(source['id']));
      });
    }
    title.dispose();
    text.dispose();
  }

  Future<void> previewSource(Map<String, dynamic> source) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: DefaultTabController(
          length: source['document'] != null ? 2 : 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        source['title'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close source',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              TabBar(
                tabs: [
                  const Tab(text: 'Notes'),
                  if (source['document'] != null) const Tab(text: 'PDF'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        (source['notes'] as String).isEmpty
                            ? 'This source contains a PDF. Open its PDF tab to read it.'
                            : source['notes'],
                      ),
                    ),
                    if (source['document'] != null)
                      PdfScreen(
                        controller: c,
                        document: Map<String, dynamic>.from(source['document']),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> citation(Map<String, dynamic> cite) async {
    final source = c.sets.where((s) => s['id'] == cite['setId']).firstOrNull;
    final changed = source == null || source['version'] != cite['version'];
    final isPdf = cite['page'] != null;
    final canOpen =
        source != null &&
        (!isPdf || source['document']?['id'] == cite['sourceId']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.format_quote, color: accent),
            const SizedBox(width: 12),
            Expanded(child: Text(cite['title'])),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPdf)
                  Text(
                    'Page ${cite['page']}',
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 16),
                SelectableText(
                  '“${cite['quote']}”',
                  style: const TextStyle(height: 1.8),
                ),
                const SizedBox(height: 20),
                Text(
                  changed
                      ? 'This is the excerpt verified when the answer was generated. The original source has since changed or been removed.'
                      : 'This excerpt was checked against the text of your selected source.',
                  style: const TextStyle(fontSize: 12),
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
          if (canOpen)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (isPdf) {
                  context.go('/pdf/${source['id']}?page=${cite['page']}');
                } else {
                  previewSource(source);
                }
              },
              child: const Text('Open source'),
            ),
        ],
      ),
    );
  }

  Future<void> pin(Map<String, dynamic> entry) async {
    final blocks = entry['content']['blocks'] as List;
    final text = blocks
        .map((b) => '${b['heading']}\n${b['text']}')
        .join('\n\n');
    if (text.isEmpty) return;
    await task(() async {
      await c.saveNotebookNote(
        widget.set['id'],
        entry['kind'] == 'chat'
            ? (entry['prompt'] as String).substring(
                0,
                (entry['prompt'] as String).length.clamp(0, 150),
              )
            : label(entry['kind']),
        text,
        entryId: entry['id'],
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to Studio notes.')));
      }
    });
  }

  Future<void> newNote() async {
    final title = TextEditingController(), text = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A note for your future self'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 30000,
                  decoration: const InputDecoration(
                    labelText: 'Your note',
                    alignLabelWithHint: true,
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
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    if (save == true && mounted) {
      await task(() async {
        if (title.text.trim().isEmpty || text.text.trim().isEmpty) {
          throw ApiException(400, 'Add a title and note text.');
        }
        await c.saveNotebookNote(
          widget.set['id'],
          title.text.trim(),
          text.text.trim(),
        );
      });
    }
    title.dispose();
    text.dispose();
  }

  static String label(String kind) => switch (kind) {
    'summary' => 'Source overview',
    'guide' => 'Study guide',
    'faq' => 'Questions & answers',
    _ => 'Source conversation',
  };
  Future<void> export(String title, String text) async {
    await task(() async {
      await FilePicker.saveFile(
        fileName:
            '${title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim()}.md',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final wide = size.maxWidth >= 960;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 24 : 16,
              14,
              wide ? 24 : 16,
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go('/library'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Library'),
                    ),
                    const Spacer(),
                    IconButton(
                    Tooltip(
                      message: 'Edit notebook source',
                      child: IconButton(
                        onPressed: busy ? null : editSource,
                        icon: const Icon(
                          Icons.drive_file_rename_outline,
                          size: 20,
                        ),
                      ),
                    ),
                    if (!wide)
                      IconButton(
                        tooltip: 'Study tools',
                        onPressed: showTools,
                        icon: const Icon(Icons.tune_rounded, size: 20),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: showTools,
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: const Text('Study tools'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.set['title'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontSize: wide ? 28 : 24),
                ),
                const SizedBox(height: 6),
                Text(
                  '${validSelection.length} selected ${validSelection.length == 1 ? 'source' : 'sources'}  ·  ${entries.length} saved ${entries.length == 1 ? 'response' : 'responses'}  ·  ${savedNotes.length} ${savedNotes.length == 1 ? 'note' : 'notes'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ErrorState(message: error!)),
                  IconButton(
                    tooltip: 'Dismiss error',
                    onPressed: () => setState(() => error = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          Expanded(
            child: wide
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 218, child: panel(sources())),
                        const SizedBox(width: 14),
                        Expanded(child: panel(chat(), chatPanel: true)),
                        const SizedBox(width: 14),
                        SizedBox(width: 276, child: panel(studio())),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 0,
                              label: Text('Sources'),
                              icon: Icon(Icons.source_outlined, size: 17),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text('Chat'),
                              icon: Icon(Icons.forum_outlined, size: 17),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text('Studio'),
                              icon: Icon(Icons.auto_awesome_outlined, size: 17),
                            ),
                          ],
                          selected: {mobileTab},
                          onSelectionChanged: (v) =>
                              setState(() => mobileTab = v.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: panel(switch (mobileTab) {
                            0 => sources(),
                            2 => studio(),
                            _ => chat(),
                          }, chatPanel: mobileTab == 1),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
  Widget panel(Widget child, {bool chatPanel = false}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: chatPanel
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .6),
      ),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget panelTitle(String title, IconData icon, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 20, 12, 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        ?action,
      ],
    ),
  );
  Widget sources() {
    final filtered = c.sets
        .where(
          (s) => '${s['title']} ${s['folder']}'.toLowerCase().contains(
            sourceSearch.text.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panelTitle(
          'Sources',
          Icons.source_outlined,
          action: Tooltip(
            message: 'Add a source',
            child: IconButton(
              onPressed: busy ? null : addSource,
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: OutlinedButton.icon(
            onPressed: busy ? null : addSource,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add source'),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: sourceSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Find materials',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Use up to 50 sources',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final source in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: selected.contains(source['id'])
                        ? accent.withValues(alpha: .08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: selected.contains(source['id']),
                          onChanged: busy
                              ? null
                              : (v) {
                                  if (v == true &&
                                      validSelection.length >= 50) {
                                    setState(
                                      () => error = 'Select up to 50 sources.',
                                    );
                                    return;
                                  }
                                  setState(() {
                                    if (v == true) {
                                      selected.add(source['id']);
                                    } else {
                                      selected.remove(source['id']);
                                    }
                                  });
                                },
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => previewSource(source),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 12, 10, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source['title'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Icon(
                                        source['document'] == null
                                            ? Icons.notes_rounded
                                            : Icons.picture_as_pdf_outlined,
                                        size: 12,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          source['document'] == null
                                              ? 'Lecture notes'
                                              : 'PDF + notes',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (source['pending'] == true)
                                    const Text(
                                      'Waiting to sync',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: accent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Only checked sources are sent for notebook answers. PDFs need selectable text.',
            style: TextStyle(
              fontSize: 10,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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

  Widget storageMeter() {
    final value = widget.set['capacity'] as Map? ?? {};
    final used = (value['pdfBytes'] as num? ?? 0).toDouble(),
        limit = (value['pdfLimitBytes'] as num? ?? 2147483648).toDouble();
    final label = used >= 1073741824
        ? '${(used / 1073741824).toStringAsFixed(2)} GiB'
        : used >= 1048576
        ? '${(used / 1048576).toStringAsFixed(1)} MiB'
        : '${(used / 1024).toStringAsFixed(0)} KiB';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Room for your next idea',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('$label of 2 GiB PDFs', style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (used / limit).clamp(0, 1),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${value['sources'] ?? 0}/50 attached sources · ${savedNotes.length}/50 saved notes',
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
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
            storageMeter(),
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
            ),
            if ((widget.set['collections'] as List? ?? []).isEmpty)
              TextButton.icon(
                onPressed: showTools,
                icon: const Icon(Icons.quiz_outlined, size: 17),
                label: const Text(
                  'Create quizzes & cards',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            for (final collection in widget.set['collections'] ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  collection['kind'] == 'flashcards'
                      ? Icons.style_outlined
                      : Icons.quiz_outlined,
                  color: accent,
                  size: 18,
                ),
                title: Text(
                  collection['title'],
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.play_arrow_rounded, size: 18),
                onTap: () => context.go(
                  '/${collection['kind'] == 'flashcards' ? 'cards' : 'quiz'}/${widget.set['id']}?collection=${Uri.encodeQueryComponent(collection['id'])}',
                ),
              ),
            for (final entry in entries.where((e) => e['kind'] != 'chat'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(
                  Icons.description_outlined,
                  color: accent,
                  size: 18,
                ),
                title: Text(
                  label(entry['kind']),
                  style: const TextStyle(fontSize: 11),
                ),
                subtitle: Text(
                  DateTime.fromMillisecondsSinceEpoch(entry['created_at'])
                      .toLocal()
                      .toString()
                      .split('.')
                      .first,
                  style: const TextStyle(fontSize: 9),
                ),
                trailing: const Icon(Icons.chevron_right, size: 17),
                onTap: () => setState(() {
                  report = Map<String, dynamic>.from(entry);
                  mobileTab = 1;
                }),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved notes · ${savedNotes.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Write a note',
                  onPressed: busy ? null : newNote,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
            if (savedNotes.isEmpty)
              Text(
                'Save an answer or write a thought you don’t want to lose.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (final note in savedNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    dense: true,
                    title: Text(
                      note['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      note['pending'] == true
                          ? 'Saved offline · waiting to sync'
                          : note['text'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(note['title']),
                        content: SizedBox(
                          width: 560,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SelectableText(note['text']),
                                const SizedBox(height: 16),
                                for (final cite in note['citations'] ?? [])
                                  TextButton.icon(
                                    onPressed: () => citation(
                                      Map<String, dynamic>.from(cite),
                                    ),
                                    icon: const Icon(
                                      Icons.format_quote,
                                      size: 16,
                                    ),
                                    label: Text(cite['title']),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              task(
                                () => c.deleteNotebookNote(
                                  widget.set['id'],
                                  note['id'],
                                ),
                              );
                            },
                            child: const Text('Delete note'),
                          ),
                          TextButton(
                            onPressed: () =>
                                export(note['title'], note['text']),
                            child: const Text('Export'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
  @override
  void dispose() {
    composer.dispose();
    sourceSearch.dispose();
    composerFocus.dispose();
    chatScroll.dispose();
    super.dispose();
  }
}
