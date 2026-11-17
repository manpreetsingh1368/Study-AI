import 'package:material_ui/material_ui.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class IdentitySettings extends StatefulWidget {
  final StudyController controller;
  const IdentitySettings({super.key, required this.controller});
  @override
  State<IdentitySettings> createState() => _IdentitySettingsState();
}

class _IdentitySettingsState extends State<IdentitySettings> {
  Map<String, dynamic> options = {};
  List<dynamic> identities = [];
