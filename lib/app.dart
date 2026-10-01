import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'services/app_services.dart';

class ColorGravityApp extends StatefulWidget {
  const ColorGravityApp({super.key, required this.services});
  final AppServices services;

  @override
  State<ColorGravityApp> createState() => _ColorGravityAppState();
}

class _ColorGravityAppState extends State<ColorGravityApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = widget.services;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      s.audio.pauseAll();
      s.progress.flush();
    } else if (state == AppLifecycleState.resumed) {
      s.audio.resumeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        title: 'Color Gravity',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        builder: (context, child) {
          // Clamp text scaling so layouts stay intact at large system sizes.
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2)),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
