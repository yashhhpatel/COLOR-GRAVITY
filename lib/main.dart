import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final services = await AppServices.createReal();
  runApp(ColorGravityApp(services: services));
}
