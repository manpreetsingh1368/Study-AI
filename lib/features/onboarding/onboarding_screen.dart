import 'package:material_ui/material_ui.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class OnboardingScreen extends StatefulWidget {
  final StudyController controller;
  const OnboardingScreen({super.key, required this.controller});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  bool busy = false;
  String? error;
  static const pages = [
    (
      Icons.auto_stories_outlined,
      'A workspace for your next idea.',
      'Save lecture notes and PDFs in a private library that follows your account across devices.',
    ),
    (
      Icons.auto_awesome_outlined,
      'Learn by doing.',
      'Create quizzes, flashcards and practice exams with Gemini. Source material selected for generation is sent to Google; review its privacy terms before use.',
    ),
    (
      Icons.cloud_done_outlined,
      'Keep learning, even offline.',
      'Downloaded notes, PDFs and learning collections remain available offline. Your edits and study progress synchronize when your self-hosted backend is reachable.',
    ),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: StudyCard(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(pages[step].$1, color: accent, size: 64),
                const SizedBox(height: 32),
                Text(
                  pages[step].$2,
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(pages[step].$3, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                Text(
                  '${step + 1} / ${pages.length}',
                  style: const TextStyle(color: accent),
                ),
                const SizedBox(height: 24),
                if (error != null) ErrorState(message: error!),
                Wrap(
                  spacing: 12,
                  children: [
                    if (step > 0)
                      TextButton(
                        onPressed: busy ? null : () => setState(() => step--),
                        child: const Text('Back'),
                      ),
                    PrimaryActionButton(
                      label: step == 2 ? 'Open my workspace' : 'Continue',
                      icon: Icons.arrow_forward,
                      onPressed: busy
                          ? null
                          : () async {
                              if (step < 2) {
                                setState(() => step++);
                              } else {
                                setState(() => busy = true);
                                try {
                                  await widget.controller.completeOnboarding();
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = e.toString());
                                  }
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
