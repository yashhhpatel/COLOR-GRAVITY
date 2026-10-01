import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../widgets/common/logo.dart';
import '../../widgets/common/ui.dart';
import '../home/home_screen.dart';
import '../onboarding/intro_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), _go);
  }

  void _go() {
    if (!mounted) return;
    final s = AppScope.of(context);
    final first = !s.progress.data.onboardingDone;
    if (!first) s.audio.playMusic(MusicTrack.home);
    Navigator.of(context).pushReplacement(fadeRoute(first ? const IntroScreen() : const HomeScreen()));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
              child: const GameLogo(),
            ),
          ),
        ),
      ),
    );
  }
}
