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
