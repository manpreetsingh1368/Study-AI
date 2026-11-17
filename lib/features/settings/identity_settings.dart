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
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.controller.request('GET', '/me/identities'),
          config = await widget.controller.request('GET', '/auth/options');
      if (mounted) {
        setState(() {
          identities = data['identities'];
          options = Map<String, dynamic>.from(config);
