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
