import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central design tokens. UI chrome stays neutral (deep navy + white) so the
/// gameplay colors always own the most saturated part of the screen.
class AppColors {
  static const Color bg = Color(0xFF0A0E1C);
  static const Color bgDeep = Color(0xFF060914);
  static const Color surface = Color(0xFF141A2E);
  static const Color surfaceHigh = Color(0xFF1C2440);
  static const Color stroke = Color(0x1FFFFFFF);
  static const Color strokeStrong = Color(0x33FFFFFF);

  static const Color text = Color(0xFFF3F5FF);
  static const Color textDim = Color(0xFFA3ABCC);
  static const Color textMute = Color(0xFF6B7396);

  static const Color brand = Color(0xFF7B6CFF);
  static const Color brand2 = Color(0xFF4FA3FF);
  static const Color coin = Color(0xFFFFC23D);
  static const Color star = Color(0xFFFFD45C);
  static const Color success = Color(0xFF39E09B);
  static const Color danger = Color(0xFFFF5470);
  static const Color locked = Color(0xFF39405E);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF8B6BFF), Color(0xFF4F8CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient playGradient = LinearGradient(
    colors: [Color(0xFF9A7BFF), Color(0xFF5C7CFF), Color(0xFF3FB6FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppText {
  static const String family = 'Inter';

  static const TextStyle display = TextStyle(
      fontFamily: family, fontSize: 40, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.5, height: 1.05);
  static const TextStyle title =
      TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.2);
  static const TextStyle heading =
      TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text);
  static const TextStyle body =
      TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.35);
  static const TextStyle bodyDim =
      TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textDim, height: 1.35);
  static const TextStyle label =
      TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim, letterSpacing: 1.1);
  static const TextStyle button =
      TextStyle(fontFamily: family, fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.4);
  static const TextStyle number = TextStyle(
      fontFamily: family,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
      fontFeatures: [FontFeature.tabularFigures()]);
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppText.family,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brand,
        secondary: AppColors.brand2,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
    );
    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textDim),
        trackColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: AppText.body,
        behavior: SnackBarBehavior.floating,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgDeep,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
