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

