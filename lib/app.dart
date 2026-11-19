import 'package:flutter/material.dart';

import 'core/smooth_scroll.dart';
import 'screens/splash/splash_screen.dart';
import 'widgets/aurora_background.dart';
import 'widgets/title_bar.dart';
import 'core/platform.dart';

/// Lets code outside the widget tree (the benchmark) reach the navigator.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VeloraApp extends StatelessWidget {
  const VeloraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Velora',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const VeloraScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'SF Pro Display',
        fontFamilyFallback: const ['Inter', 'Segoe UI'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
      ),
      // One aurora behind every route so it never restarts on navigation.
      builder: (context, child) => AuroraBackground(child: child!),
      home: const _SplashWithCaption(),
    );
  }
}

/// Splash plus a caption bar (the home screen draws its own with the logo).
class _SplashWithCaption extends StatelessWidget {
  const _SplashWithCaption();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SplashScreen(),
        if (isDesktop)
          const Positioned(top: 0, left: 0, right: 0, child: VeloraTitleBar()),
      ],
    );
  }
}
