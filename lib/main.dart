import 'package:flutter/material.dart';

import 'l10n/app_strings.dart';
import 'screens/home_screen.dart';
import 'services/embedded_fonts.dart';
import 'services/play_force_update.dart';

final LocaleController localeController = LocaleController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmbeddedFonts.instance.load();
  await localeController.load();
  await forcePlayUpdateIfNeeded();
  runApp(const PdfWordEditorApp());
}

class PdfWordEditorApp extends StatelessWidget {
  const PdfWordEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: localeController,
      child: ListenableBuilder(
        listenable: localeController,
        builder: (context, _) {
          final s = localeController.strings;
          return MaterialApp(
            title: s.appName,
            locale: localeController.locale,
            supportedLocales: const [Locale('en'), Locale('el')],
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3A5CE0)),
              scaffoldBackgroundColor: const Color(0xFFF4F5F9),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                elevation: 0,
                scrolledUnderElevation: 2,
                centerTitle: false,
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
