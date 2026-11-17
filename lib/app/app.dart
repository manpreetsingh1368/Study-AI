import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/study_controller.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/recovery_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/dashboard/workspace.dart';
import '../shared/components.dart';

class StudyAIApp extends ConsumerStatefulWidget {
  const StudyAIApp({super.key});
  @override
  ConsumerState<StudyAIApp> createState() => _StudyAIAppState();
}

class _StudyAIAppState extends ConsumerState<StudyAIApp> {
  late GoRouter router;
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    final c = ref.read(studyProvider);
    router = GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: c,
      redirect: (context, state) {
        if (c.loading) return state.uri.path == '/splash' ? null : '/splash';
        if (!c.onboarded) {
          return state.uri.path == '/welcome' ? null : '/welcome';
        }
        if (c.user == null) {
          return ['/login', '/recovery'].contains(state.uri.path)
              ? null
              : '/login';
        }
        if (state.uri.path == '/login' ||
            state.uri.path == '/splash' ||
            state.uri.path == '/welcome') {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => ForgotPasswordScreen(controller: c),
        GoRoute(
          path: '/recovery',
          builder: (_, _) => RecoveryScreen(controller: c),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => OnboardingScreen(controller: c),
        ),
        GoRoute(
          path: '/splash',
          builder: (_, _) => const Scaffold(body: LoadingState()),
        ),
        GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
        GoRoute(
          path: '/:page',
          builder: (_, s) => Workspace(
            page: s.pathParameters['page']!,
            mode: ThemeMode.values.firstWhere(
              (m) => m.name == c.appearance,
              orElse: () => ThemeMode.system,
            ),
            onTheme: (m) => c.setAppearance(m.name),
          ),
        ),
        GoRoute(
          path: '/:page/:id',
          builder: (_, s) => Workspace(
            page: s.pathParameters['page']!,
            setId: s.pathParameters['id'],
            mode: ThemeMode.values.firstWhere(
              (m) => m.name == c.appearance,
              orElse: () => ThemeMode.system,
            ),
            onTheme: (m) => c.setAppearance(m.name),
          ),
        ),
      ],
    );
  }

  ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: b,
        surface: dark ? const Color(0xFF20202B) : Colors.white,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF16161F)
          : const Color(0xFFF5F5FA),
      fontFamily: 'sans',
      dividerColor: dark ? Colors.white24 : Colors.black12,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: dark ? Colors.white10 : const Color(0xFFE9E8F1),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: .04)
            : const Color(0xFFF4F3F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        headlineSmall: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
        bodyMedium: TextStyle(height: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ref.read(studyProvider),
    builder: (context, _) => MaterialApp.router(
      title: 'Study AI',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == ref.read(studyProvider).appearance,
        orElse: () => ThemeMode.system,
      ),
      routerConfig: router,
    ),
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }
}
