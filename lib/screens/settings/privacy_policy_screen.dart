import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/ui.dart';

/// In-app privacy policy (works offline). Mirrors PRIVACY.md in the repo.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<(String, String)> sections = [
    (
      'Overview',
      'Color Gravity is an offline game. You do not need an account, and the game does not ask for your name, '
          'email, contacts, location, camera, microphone or files.'
    ),
    (
      'Data stored on your device',
      'Your progress (levels, stars, coins, achievements, cosmetics, daily streak, endless records), your settings '
          '(music, sound, vibration, controls) and your Ads-Free status are saved only on your device. Uninstalling the '
          'game deletes this data.'
    ),
    (
      'Advertising',
      'The free version shows ads from Google AdMob between runs and when you choose to watch a rewarded ad. Ads are '
          'never shown during gameplay. AdMob may collect device identifiers (such as the advertising ID), approximate '
          'location from IP address and ad interaction data to serve and measure ads. See Google\'s policy at '
          'policies.google.com/technologies/ads. You can reset or opt out of personalized ads in your Android settings.'
    ),
    (
      'Purchases',
      'Ads-Free plans (1 Month and Lifetime) are processed entirely by Google Play. We never see or store your payment '
          'details. Google Play only tells the game which plan you own so it can turn ads off.'
    ),
    ('Children', 'The game is not directed at children under 13 and does not knowingly collect personal information from them.'),
    ('Changes', 'If this policy changes, the updated version will be published in the app and on the game\'s store listing.'),
    ('Contact', 'Questions about privacy? Email ${AppConfig.contactEmail}.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: Column(children: [
            const ScreenHeader(title: 'Privacy Policy'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                itemCount: sections.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == sections.length) {
                    return Center(
                      child: Text('Last updated: October 2026', style: AppText.label.copyWith(color: AppColors.textMute)),
                    );
                  }
                  final (title, body) = sections[i];
                  return FadeSlideIn(
                    delay: FadeSlideIn.stagger(i),
                    child: GlassCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: AppText.heading.copyWith(fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(body, style: AppText.bodyDim),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
