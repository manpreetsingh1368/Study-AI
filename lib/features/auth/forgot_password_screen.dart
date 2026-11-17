import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final StudyController controller;
  const ForgotPasswordScreen({super.key, required this.controller});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final email = TextEditingController(
    text: widget.controller.user?['email'],
  );
  final form = GlobalKey<FormState>();
  bool busy = false, sent = false;
  String? message;
