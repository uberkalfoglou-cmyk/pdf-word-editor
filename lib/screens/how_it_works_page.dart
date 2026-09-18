import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

const howItWorksSeenKey = 'how_it_works_seen';

class HowItWorksPage extends StatelessWidget {
  const HowItWorksPage({super.key, required this.onDone});

  final VoidCallback onDone;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(howItWorksSeenKey, true);
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          const LanguagePickerButton(),
          TextButton(
            onPressed: _finish,
            child: Text(s.skip),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.howItWorks,
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                s.howItWorksIntro,
                style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              _Step(number: '1', title: s.step1Title, detail: s.step1Detail),
              _Step(number: '2', title: s.step2Title, detail: s.step2Detail),
              _Step(number: '3', title: s.step3Title, detail: s.step3Detail),
              const Spacer(),
              FilledButton(
                onPressed: _finish,
                child: Text(s.gotIt),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: Text(number, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(detail, style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
