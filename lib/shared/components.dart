import 'dart:ui';

import 'package:material_ui/material_ui.dart';

const accent = Color(0xFF7660DC);

class StudyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const StudyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: padding, child: child),
  );
}

class PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class LoadingState extends StatelessWidget {
  final String label;
  const LoadingState({super.key, this.label = 'Getting your workspace ready…'});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(label),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, description;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.title,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.auto_stories_outlined, size: 44, color: accent),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(description, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  final String message;
  const ErrorState({super.key, required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}

class GlassSidebar extends StatelessWidget {
  final Widget child;
  const GlassSidebar({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        width: 232,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .8),
          border: Border(
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .1),
            ),
          ),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}

class ModernToolbar extends StatelessWidget {
  final String title, status;
  final VoidCallback? onOpenSearch;
  final VoidCallback onSync;
  final ValueChanged<String> onSearch;
  const ModernToolbar({
    super.key,
    required this.title,
    required this.status,
    required this.onSync,
    required this.onSearch,
    this.onOpenSearch,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    child: Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (MediaQuery.sizeOf(context).width > 800)
          SizedBox(
            width: 240,
            child: onOpenSearch != null
                ? OutlinedButton.icon(
                    onPressed: onOpenSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search library · ⌘/Ctrl K'),
                  )
                : TextField(
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      hintText: 'Search your library',
                      prefixIcon: Icon(Icons.search, size: 19),
                      isDense: true,
                    ),
                  ),
          ),
        const SizedBox(width: 12),
        Tooltip(
          message: status,
          child: IconButton(
            onPressed: onSync,
            icon: const Icon(Icons.sync, size: 20),
          ),
        ),
      ],
    ),
  );
}

class DocumentUploadArea extends StatelessWidget {
  final VoidCallback? onTap;
  final String? filename;
  const DocumentUploadArea({super.key, this.onTap, this.filename});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Select PDF document',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(16),
          color: accent.withValues(alpha: .04),
        ),
        child: Column(
          children: [
            const Icon(Icons.upload_file_outlined, color: accent, size: 32),
            const SizedBox(height: 12),
            Text(
              filename ?? 'Choose a PDF',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}

class QuizQuestionCard extends StatelessWidget {
  final Map<String, dynamic> question;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final bool reveal;
  const QuizQuestionCard({
    super.key,
    required this.question,
    this.selected,
    this.onSelect,
    this.reveal = false,
  });
  @override
  Widget build(BuildContext context) => StudyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question['topic'],
          style: const TextStyle(color: accent, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Text(
          question['question'],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(18),
                backgroundColor: reveal && question['answer'] == i
                    ? Colors.green.withValues(alpha: .15)
                    : selected == i
                    ? accent.withValues(alpha: .15)
                    : null,
              ),
              onPressed: onSelect == null ? null : () => onSelect!(i),
              child: Text(
                '${String.fromCharCode(65 + i)}.  ${question['choices'][i]}',
              ),
            ),
          ),
        if (reveal) Text(question['explanation']),
      ],
    ),
  );
}

class FlashcardWidget extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool flipped;
  final VoidCallback onFlip;
  const FlashcardWidget({
    super.key,
    required this.card,
    required this.flipped,
    required this.onFlip,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Flip flashcard',
    child: GestureDetector(
      onTap: onFlip,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(flipped),
          constraints: const BoxConstraints(minHeight: 280),
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: .3)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  flipped ? 'ANSWER' : 'PROMPT',
                  style: const TextStyle(
                    color: accent,
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  card[flipped ? 'back' : 'front'],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 28),
                const Text(
                  'Tap or press Space to flip',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProgressChart extends StatelessWidget {
  final List<double> values;
  const ProgressChart({super.key, required this.values});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 130,
    child: values.isEmpty
        ? const Center(child: Text('Complete a quiz to see your trend.'))
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final value in values)
                Expanded(
                  child: Tooltip(
                    message: '${value.round()}%',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: (value.clamp(0, 100) * 1.1 + 6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class SubscriptionCard extends StatelessWidget {
  final String name, description;
  final Widget? action;
  const SubscriptionCard({
    super.key,
    required this.name,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => StudyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.auto_awesome, color: accent),
        const SizedBox(height: 16),
        Text(name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(description),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
