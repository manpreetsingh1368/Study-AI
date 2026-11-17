import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class ShareNotebookSheet extends StatefulWidget {
  final StudyController controller;
  final Map<String, dynamic> notebook;
  const ShareNotebookSheet({
    super.key,
    required this.controller,
    required this.notebook,
  });
  @override
  State<ShareNotebookSheet> createState() => _ShareNotebookSheetState();
}

class _ShareNotebookSheetState extends State<ShareNotebookSheet> {
  final entries = <String>{}, notes = <String>{};
  bool source = false, busy = false;
  int days = 7;
  String? error, url;
  List<dynamic> links = [];
  StudyController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await c.request(
        'GET',
        '/notebooks/${widget.notebook['id']}/shares',
      );
      if (mounted) setState(() => links = data['shares']);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> create() async {
    setState(() => busy = true);
    try {
      final link = await c.createShare(
        widget.notebook['id'],
        includeSourceNotes: source,
        entryIds: entries.toList(),
        noteIds: notes.toList(),
        days: days,
      );
      if (mounted) setState(() => url = link['url']);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.notebook['notebook'] as Map? ?? {};
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 14, 12),
            child: Row(
              children: [
                const Icon(Icons.ios_share_rounded, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share your understanding',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close sharing',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anyone with the link · read-only',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Choose exactly what to share. A link publishes a snapshot, not your account or original PDFs. Later edits aren’t published. You can revoke the link anytime.',
                        style: TextStyle(fontSize: 12, height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (error != null) ...[
                  ErrorState(message: error!),
                  const SizedBox(height: 16),
                ],
                if ((widget.notebook['notes'] as String).isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include notebook source notes'),
                    subtitle: Text(
                      widget.notebook['notes'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: source,
                    onChanged: busy ? null : (v) => setState(() => source = v!),
                  ),
                for (final item in book['notes'] ?? [])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['title']),
                    subtitle: const Text('Saved Studio note'),
                    value: notes.contains(item['id']),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            v == true
                                ? notes.add(item['id'])
                                : notes.remove(item['id']);
                          }),
                  ),
                for (final item in book['entries'] ?? [])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item['kind'] == 'chat'
                          ? item['prompt']
                          : item['kind'] == 'guide'
                          ? 'Study guide'
                          : item['kind'] == 'faq'
                          ? 'FAQ'
                          : 'Source overview',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Includes its source excerpts'),
                    value: entries.contains(item['id']),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            v == true
                                ? entries.add(item['id'])
                                : entries.remove(item['id']);
                          }),
                  ),
                const SizedBox(height: 16),
                DropdownMenu<int>(
                  initialSelection: days,
                  label: const Text('Link expires after'),
                  onSelected: busy ? null : (v) => setState(() => days = v!),
                  dropdownMenuEntries: [
                    for (final n in [1, 7, 30, 90])
                      DropdownMenuEntry(
                        value: n,
                        label: '$n ${n == 1 ? 'day' : 'days'}',
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                PrimaryActionButton(
                  label: busy ? 'Creating link…' : 'Create read-only link',
                  icon: Icons.link_rounded,
                  onPressed:
                      busy ||
                          c.offline ||
                          (!source && notes.isEmpty && entries.isEmpty)
                      ? null
                      : create,
                ),
                if (url != null) ...[
                  const SizedBox(height: 20),
                  StudyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your shareable link',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          url!,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: url!),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Link copied.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy, size: 17),
                              label: const Text('Copy link'),
                            ),
                            TextButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(url!),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 17),
                              label: const Text('Preview'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                Text(
                  'Manage existing links',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (links.isEmpty)
                  const Text(
                    'No shared links yet.',
                    style: TextStyle(fontSize: 12),
                  ),
                for (final link in links)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      link['revoked_at'] != null ? Icons.link_off : Icons.link,
                      color: accent,
                    ),
                    title: Text(
                      link['title'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      link['revoked_at'] != null
                          ? 'Revoked'
                          : 'Expires ${DateTime.fromMillisecondsSinceEpoch(link['expires_at']).toLocal().toString().split(' ').first}',
                    ),
                    trailing: link['revoked_at'] != null
                        ? null
                        : Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Copy saved link',
                                onPressed: () async {
                                  final saved = await c.secure.read(
                                    key: 'share:${c.account}:${link['id']}',
                                  );
                                  if (saved != null) {
                                    await Clipboard.setData(
                                      ClipboardData(text: saved),
                                    );
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
