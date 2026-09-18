import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(s.privacyPolicy)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text(s.privacyIntro, style: text.bodyLarge),
          const SizedBox(height: 8),
          Text(s.privacyUpdated, style: text.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 24),
          Text(s.privacyWhatTitle, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.privacyWhatBody, style: text.bodyLarge?.copyWith(color: muted)),
          const SizedBox(height: 24),
          Text(s.privacyDataTitle, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.privacyDataBody, style: text.bodyLarge?.copyWith(color: muted)),
          const SizedBox(height: 12),
          Text('• ${s.privacyBulletFiles}', style: text.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 8),
          Text('• ${s.privacyBulletLocal}', style: text.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 8),
          Text('• ${s.privacyBulletNoAccount}', style: text.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 24),
          Text(s.privacyPermTitle, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.privacyPermBody, style: text.bodyLarge?.copyWith(color: muted)),
          const SizedBox(height: 24),
          Text(s.privacyContactTitle, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.privacyContactBody, style: text.bodyLarge?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
