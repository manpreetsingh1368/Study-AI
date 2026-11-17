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
