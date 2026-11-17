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
