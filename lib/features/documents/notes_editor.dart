import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class NotesEditor extends StatefulWidget {
  final StudyController controller;
  final Map<String, dynamic>? existing;
  const NotesEditor({super.key, required this.controller, this.existing});
  @override
  State<NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<NotesEditor> {
  late final title = TextEditingController(text: widget.existing?['title']);
  late final notes = TextEditingController(text: widget.existing?['notes']);
  PlatformFile? pdf;
  String? droppedName;
  List<int>? droppedBytes;
  late final folder = TextEditingController(
    text: widget.existing?['folder'] ?? '',
  );
  Map<String, dynamic>? savedSet;
  bool busy = false;
  String? error;
  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Give your study set a title.');
      return;
    }
    setState(() => busy = true);
    try {
      final s = await widget.controller.saveSet(
        title.text.trim(),
        notes.text,
        existing: savedSet ?? widget.existing,
        folder: folder.text.trim(),
      );
      savedSet = s;
      if (pdf != null || droppedBytes != null) {
        await widget.controller.upload(
          s['id'],
          droppedName ?? pdf!.name,
          droppedBytes ?? await pdf!.readAsBytes(),
        );
      }
      if (mounted) {
        if (widget.existing != null) {
          Navigator.of(context).pop();
        } else {
          context.go('/set/${s['id']}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Text(
        widget.existing == null
            ? 'Make space for a new idea.'
            : 'Edit study material',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      const Text('Paste your lecture notes, attach a PDF, or bring both.'),
      const SizedBox(height: 28),
      StudyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Study set title',
                hintText: 'e.g. Introduction to neuroscience',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: folder,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Folder (optional)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notes,
              maxLines: 12,
              maxLength: 100000,
              decoration: const InputDecoration(
                labelText: 'Your notes',
                alignLabelWithHint: true,
                hintText: 'What are we learning today?',
              ),
            ),
            const SizedBox(height: 20),
            DropTarget(
              onDragDone: (details) async {
                if (busy || details.files.length != 1) return;
                final file = details.files.single;
                if (!file.name.toLowerCase().endsWith('.pdf') ||
                    await file.length() > 10485760) {
                  if (mounted) {
                    setState(() => error = 'Drop one PDF smaller than 10 MB.');
                  }
                  return;
                }
                final bytes = await file.readAsBytes();
                if (mounted) {
                  setState(() {
                    droppedName = file.name;
                    droppedBytes = bytes;
                    pdf = null;
                  });
                }
              },
              child: DocumentUploadArea(
                filename:
                    droppedName ??
                    pdf?.name ??
                    (widget.existing?['document'] != null
                        ? 'Choose a replacement PDF'
                        : null),
                onTap: busy
                    ? null
                    : () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf'],
                        );
                        if (result.isNotEmpty && mounted) {
                          if ((await result.single.length() ?? 10485761) >
                              10485760) {
                            setState(
                            );
                          } else {
                            setState(() {
                              pdf = result.single;
                              droppedName = null;
                              droppedStream = null;
                              droppedLength = null;
                            });
                          }
                        }
                      },
              ),
            ),
            const SizedBox(height: 24),
            if (error != null) ...[
              ErrorState(message: error!),
              const SizedBox(height: 16),
            ],
            PrimaryActionButton(
              label: busy ? 'Saving…' : 'Save study set',
              icon: Icons.check_rounded,
              onPressed: busy ? null : save,
            ),
          ],
        ),
      ),
    ],
  );
  @override
  void dispose() {
    folder.dispose();
    title.dispose();
    notes.dispose();
    super.dispose();
  }
}
