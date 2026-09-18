import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import 'editor_screen.dart';
import 'how_it_works_page.dart';
import 'privacy_policy_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loadingPrefs = true;
  bool _showHowItWorks = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showHowItWorks = !(prefs.getBool(howItWorksSeenKey) ?? false);
      _loadingPrefs = false;
    });
  }

  Future<void> _openPdf() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          fileBytes: bytes,
          fileName: picked.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showHowItWorks) {
      return HowItWorksPage(
        onDone: () => setState(() => _showHowItWorks = false),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: const [LanguagePickerButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.edit_document,
                      size: 48,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    s.appName,
                    style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.homeTagline,
                    style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _FeatureRow(
                    icon: Icons.touch_app_outlined,
                    text: s.featureEditWord,
                    color: colorScheme,
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.open_with,
                    text: s.featureMoveWord,
                    color: colorScheme,
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.draw_outlined,
                    text: s.featureSign,
                    color: colorScheme,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.file_open),
                      label: Text(s.openPdf),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                      );
                    },
                    child: Text(s.privacyPolicy),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color.onSecondaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
