import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class StudySession extends StatefulWidget {
  final Map<String, dynamic> set;
  final bool flashcards, dueOnly;
  final String? collectionId;
  final StudyController controller;
  const StudySession({
    super.key,
    required this.set,
    required this.flashcards,
    required this.controller,
    this.collectionId,
    this.dueOnly = false,
  });
  @override
  State<StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends State<StudySession> {
  int index = 0, seconds = 0;
  bool flipped = false,
      finished = false,
      busy = false,
      ready = false,
      immediate = false,
      incorrectOnly = false;
  String attemptId = const Uuid().v4();
  String? error, sessionId;
  int? deadline;
  Map<String, int> answers = {};
  Map<String, dynamic>? result;
  late List<Map<String, dynamic>> items;
  Timer? timer;
  StudyController get c => widget.controller;
  String get draftKey =>
      'draft:${widget.set['id']}:${widget.collectionId ?? 'all'}';
  bool get exam => (widget.set['collections'] as List? ?? []).any(
    (x) => x['id'] == widget.collectionId && x['kind'] == 'exam',
  );
  @override
  void initState() {
    super.initState();
    items = (widget.set[widget.flashcards ? 'flashcards' : 'questions'] as List)
        .where(
          (q) =>
              widget.collectionId == null ||
              q['collection_id'] == widget.collectionId,
        )
        .where((q) => !widget.flashcards || !widget.dueOnly || c.isDue(q['id']))
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final saved = await c.store.read(c.account, draftKey);
      if (saved != null && !widget.flashcards) {
        answers = Map<String, int>.from(saved['answers']);
        index = (saved['index'] as int).clamp(
          0,
          items.isEmpty ? 0 : items.length - 1,
        );
        attemptId = saved['id'];
        deadline = saved['deadline'];
        sessionId = saved['sessionId'];
        immediate = saved['immediate'] ?? false;
      }
      if (exam && sessionId == null) {
        final active = c.activeExams
            .where((s) => s['collection_id'] == widget.collectionId)
            .firstOrNull;
        if (active != null) {
          sessionId = active['id'];
          deadline = active['deadline'];
        }
      }
      if (mounted) {
        setState(() => ready = true);
        if (deadline != null) tickTimer();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          ready = true;
          error = e.toString();
        });
    }
  }

  Future<void> draft() async {
    await c.store.write(c.account, draftKey, {
      'id': attemptId,
      'answers': answers,
      'index': index,
      'deadline': deadline,
      'sessionId': sessionId,
      'immediate': immediate,
    });
  }

  void tickTimer() {
    timer?.cancel();
    seconds = ((deadline! - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil()
        .clamp(0, 86400);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(
        () => seconds =
            ((deadline! - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil()
                .clamp(0, 86400),
      );
      if (seconds == 0) {
        timer?.cancel();
        unawaited(finish());
      }
    });
  }

  Future<void> startExam() async {
    setState(() => busy = true);
    try {
      final response = await c.request('POST', '/exams/start', {
        'id': const Uuid().v4(),
        'setId': widget.set['id'],
        'collectionId': widget.collectionId,
      });
      sessionId = response['session']['id'];
      deadline = response['session']['deadline'];
      await draft();
      if (mounted) {
        setState(() {});
        tickTimer();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void startTimer() {
    deadline = DateTime.now()
        .add(Duration(minutes: items.length))
        .millisecondsSinceEpoch;
    setState(() {});
    tickTimer();
    unawaited(draft());
  }

  void move(int delta) {
    if (items.isEmpty || busy) return;
    setState(() {
      index = (index + delta).clamp(0, items.length - 1);
      flipped = false;
    });
    if (!widget.flashcards) unawaited(draft());
  }

  Future<void> finish() async {
    if (busy || finished) return;
    timer?.cancel();
    setState(() => busy = true);
    try {
      final payload = {
        'id': attemptId,
        'setId': widget.set['id'],
        if (widget.collectionId != null) 'collectionId': widget.collectionId,
        if (sessionId != null) 'sessionId': sessionId,
        'answers': answers,
      };
      Map<String, dynamic>? authoritative;
      if (exam) {
        final response = await c.request('POST', '/attempts', payload);
        authoritative = Map<String, dynamic>.from(response['attempt']);
        await c.sync();
      } else {
        await c.record('/attempts', payload);
        authoritative = c.attempts
            .where((a) => a['id'] == attemptId)
            .firstOrNull;
      }
      final score = items.where((q) => answers[q['id']] == q['answer']).length;
      await c.store.write(c.account, draftKey, null);
      if (mounted)
        setState(() {
          finished = true;
          result =
              authoritative ??
              {'score': score, 'total': items.length, 'pending': true};
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(bool known) async {
    setState(() => busy = true);
    try {
      await c.record('/reviews', {
        'id': const Uuid().v4(),
        'cardId': items[index]['id'],
        'known': known,
      });
      if (mounted) {
        if (index == items.length - 1) {
          setState(() => finished = true);
        } else {
          setState(() {
            index++;
            flipped = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const LoadingState();
    if (items.isEmpty)
      return EmptyState(
        title: widget.dueOnly
            ? 'You’re all caught up.'
            : 'Nothing to study yet',
        description: widget.dueOnly
            ? 'There are no cards due in this collection. Your review schedule is saved across devices.'
            : 'Generate learning material from your study set first.',
      );
    if (finished)
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text(
            widget.flashcards ? 'A little wiser already.' : 'Session complete.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          if (result != null)
            Text(
              '${result!['score']} of ${result!['total']} correct${result!['pending'] == true ? ' · waiting to sync' : ''}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          const SizedBox(height: 24),
          if (widget.flashcards)
            const StudyCard(
              child: Text(
                'Reviews saved. Known cards get progressively longer intervals. Cards needing review return tomorrow.',
              ),
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Review incorrect answers only'),
              value: incorrectOnly,
              onChanged: (v) => setState(() => incorrectOnly = v),
            ),
            for (final q in items.where(
              (q) => !incorrectOnly || answers[q['id']] != q['answer'],
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: QuizQuestionCard(
                  question: q,
                  selected: answers[q['id']],
                  reveal: true,
                ),
              ),
          ],
        ],
      );
    if (exam && sessionId == null)
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text(
            'Your practice exam',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 20),
          StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${items.length} questions · ${items.length} minutes'),
                const SizedBox(height: 12),
                const Text(
                  'The timer continues if you leave. Answers are submitted to the backend for scoring. Stay connected to submit before the deadline. Submissions more than 10 seconds late receive zero.',
                ),
                const SizedBox(height: 20),
                if (error != null) ErrorState(message: error!),
                PrimaryActionButton(
                  label: busy ? 'Starting…' : 'Start timed exam',
                  icon: Icons.timer_outlined,
                  onPressed: busy || c.offline ? null : startExam,
                ),
              ],
            ),
          ),
        ],
      );
    final q = items[index];
    final reveal =
        !widget.flashcards && immediate && answers.containsKey(q['id']);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (widget.flashcards) setState(() => flipped = !flipped);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
        for (var i = 0; i < 4; i++)
          SingleActivator(
            [
              LogicalKeyboardKey.digit1,
              LogicalKeyboardKey.digit2,
              LogicalKeyboardKey.digit3,
              LogicalKeyboardKey.digit4,
            ][i],
          ): () {
            if (!widget.flashcards && !reveal) {
              setState(() => answers[q['id']] = i);
              unawaited(draft());
            }
          },
      },
      child: Focus(
        autofocus: true,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(
              widget.set['title'],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${widget.flashcards ? 'Card' : 'Question'} ${index + 1} of ${items.length}',
                ),
                if (deadline != null)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: Text(
                      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                    ),
                  ),
                if (!widget.flashcards && deadline == null)
                  TextButton(
                    onPressed: startTimer,
                    child: const Text('Start timed mode'),
                  ),
              ],
            ),
            if (!widget.flashcards && !exam && answers.isEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show explanations after each answer'),
                value: immediate,
                onChanged: (v) {
                  setState(() => immediate = v);
                  unawaited(draft());
                },
              ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (index + 1) / items.length,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 28),
            if (error != null) ...[
              ErrorState(message: error!),
              const SizedBox(height: 16),
            ],
            if (widget.flashcards)
              GestureDetector(
                onHorizontalDragEnd: (d) =>
                    move((d.primaryVelocity ?? 0) < 0 ? 1 : -1),
                child: FlashcardWidget(
                  card: q,
                  flipped: flipped,
                  onFlip: () => setState(() => flipped = !flipped),
                ),
              )
            else
              QuizQuestionCard(
                question: q,
                selected: answers[q['id']],
                reveal: reveal,
                onSelect: reveal
                    ? null
                    : (v) {
                        setState(() => answers[q['id']] = v);
                        unawaited(draft());
                      },
              ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: index > 0 && !busy ? () => move(-1) : null,
                  child: const Text('Previous'),
                ),
                if (widget.flashcards) ...[
                  OutlinedButton(
                    onPressed: busy ? null : () => review(false),
                    child: const Text('Needs review'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => review(true),
                    child: const Text('I know this'),
                  ),
                ] else if (index < items.length - 1)
                  FilledButton(
                    onPressed: busy ? null : () => move(1),
                    child: const Text('Next question'),
                  )
                else
                  FilledButton(
                    onPressed: busy ? null : finish,
                    child: Text(busy ? 'Saving…' : 'Finish quiz'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}

class AttemptReviewScreen extends StatelessWidget {
  final Map<String, dynamic> attempt;
  const AttemptReviewScreen({super.key, required this.attempt});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Text(
        attempt['title'] ?? 'Quiz result',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      Text('${attempt['score']} / ${attempt['total']} correct'),
      const SizedBox(height: 24),
      for (final q in attempt['questions'] ?? [])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: QuizQuestionCard(
            question: Map<String, dynamic>.from(q),
            selected: q['selected'],
            reveal: true,
          ),
        ),
    ],
  );
}
