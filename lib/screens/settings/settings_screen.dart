import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/app_services.dart';
import '../../services/monetization_controller.dart';
import '../../services/purchases/purchase_service.dart';
import '../../widgets/common/ui.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  AdFreePlan? _buying;

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showToast(context, 'Could not open link');
    } catch (_) {
      if (mounted) showToast(context, 'Could not open link');
    }
  }

  /// Opens the hosted privacy policy; falls back to the in-app copy offline.
  Future<void> _openPrivacy() async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) Navigator.of(context).push(fadeRoute(const PrivacyPolicyScreen()));
  }

  Future<void> _buy(AdFreePlan plan) async {
    final m = AppScope.of(context).monetization;
    setState(() {
      _busy = true;
      _buying = plan;
    });
    final o = await m.buy(plan);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _buying = null;
    });
    final msg = switch (o) {
      PurchaseOutcome.success => '${plan.title} activated. Thank you!',
      PurchaseOutcome.alreadyOwned => 'You already have ${plan.title}',
      PurchaseOutcome.pending => 'Payment pending. Ads-Free turns on once Google Play confirms it',
      PurchaseOutcome.cancelled => 'Purchase cancelled',
      PurchaseOutcome.unavailable => 'Google Play is unavailable right now',
      PurchaseOutcome.failed => 'Purchase failed. Please try again',
    };
    showToast(context, msg, icon: o == PurchaseOutcome.success ? Icons.check_circle_rounded : Icons.info_outline_rounded);
  }

  Future<void> _restore() async {
    final m = AppScope.of(context).monetization;
    setState(() => _busy = true);
    final found = await m.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(
      context,
      found.isEmpty ? 'No previous purchases found' : 'Restored: ${found.map((p) => p.title).join(', ')}',
      icon: found.isEmpty ? Icons.info_outline_rounded : Icons.check_circle_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([s.settings, s.monetization]),
            builder: (context, _) {
              final st = s.settings;
              final m = s.monetization;
              return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                const ScreenHeader(title: 'Settings'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SectionLabel('Audio & Feel'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Column(children: [
                        _SwitchRow(
                            icon: Icons.music_note_rounded, title: 'Music', value: st.music, onChanged: (v) => st.music = v),
                        _divider(),
                        _SwitchRow(
                            icon: Icons.volume_up_rounded, title: 'Sound effects', value: st.sfx, onChanged: (v) => st.sfx = v),
                        _divider(),
                        _SwitchRow(
                            icon: Icons.vibration_rounded,
                            title: 'Vibration',
                            value: st.vibration,
                            onChanged: (v) => st.vibration = v),
                      ]),
                    ),
                    const SectionLabel('Controls'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: _SwitchRow(
                        icon: Icons.gamepad_rounded,
                        title: 'Gravity buttons',
                        subtitle: 'Show on-screen arrows in addition to swipes',
                        value: st.gravityPad,
                        onChanged: (v) => st.gravityPad = v,
                      ),
                    ),
                    const SectionLabel('Ads-Free'),
                    FadeSlideIn(
                        delay: const Duration(milliseconds: 120),
                        child: _AdsFreeSection(
                          monetization: m,
                          busy: _busy,
                          buying: _buying,
                          onBuy: _buy,
                          onRestore: _restore,
                        )),
                    const SectionLabel('About'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Column(children: [
                        _LinkRow(
                            icon: Icons.star_rate_rounded, title: 'Rate Us', onTap: () => _open(Uri.parse(AppConfig.storeUrl))),
                        _divider(),
                        _LinkRow(
                          icon: Icons.mail_rounded,
                          title: 'Contact Us',
                          subtitle: AppConfig.contactEmail,
                          onTap: () => _open(Uri(
                            scheme: 'mailto',
                            path: AppConfig.contactEmail,
                            query: 'subject=${Uri.encodeComponent('Color Gravity support')}',
                          )),
                        ),
                        if (m.ads.privacyOptionsRequired) ...[
                          _divider(),
                          _LinkRow(
                            icon: Icons.tune_rounded,
                            title: 'Ad privacy options',
                            subtitle: 'Change your ad consent choices',
                            onTap: () => m.ads.showPrivacyOptions(),
                          ),
                        ],
                        _divider(),
                        _LinkRow(icon: Icons.privacy_tip_rounded, title: 'Privacy Policy', onTap: _openPrivacy),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Center(child: Text('Color Gravity · v1.0.1', style: AppText.label.copyWith(color: AppColors.textMute))),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 52, color: AppColors.stroke);
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, required this.value, required this.onChanged, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.text),
        title: Text(title, style: AppText.body),
        subtitle: subtitle == null ? null : Text(subtitle!, style: AppText.bodyDim.copyWith(fontSize: 12.5)),
        trailing: Switch(
            value: value,
            onChanged: (v) {
              uiFeedback(context);
              onChanged(v);
            }),
        onTap: () {
          uiFeedback(context);
          onChanged(!value);
        },
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: AppColors.text),
        title: Text(title, style: AppText.body),
        subtitle: subtitle == null ? null : Text(subtitle!, style: AppText.bodyDim.copyWith(fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMute),
        onTap: onTap == null
            ? null
            : () {
                uiFeedback(context);
                onTap!();
              },
      );
}

/// The two Ads-Free plans (Google Play Billing) + restore.
class _AdsFreeSection extends StatelessWidget {
  const _AdsFreeSection({
    required this.monetization,
    required this.busy,
    required this.buying,
    required this.onBuy,
    required this.onRestore,
  });
  final MonetizationController monetization;
  final bool busy;
  final AdFreePlan? buying;
  final void Function(AdFreePlan) onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final m = monetization;
    final until = m.monthlyUntil;
    final status = m.lifetimeOwned
        ? 'Lifetime Ads-Free is active. Thank you!'
        : m.monthlyActive && until != null
            ? 'Ads-Free active until ${until.day}/${until.month}/${until.year} (renews automatically)'
            : 'Play without ads. Gameplay is identical either way.';
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Row(key: ValueKey(status), children: [
            Icon(m.adsRemoved ? Icons.verified_rounded : Icons.block_rounded,
                color: m.adsRemoved ? AppColors.success : AppColors.textDim, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(status, style: AppText.bodyDim)),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: m.lifetimeOwned
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  const SizedBox(height: 12),
                  _PlanTile(
                    plan: AdFreePlan.monthly,
                    price: m.priceOf(AdFreePlan.monthly),
                    subtitle: 'Auto-renews monthly. Cancel anytime in Google Play',
                    owned: m.monthlyActive,
                    loading: buying == AdFreePlan.monthly,
                    onTap: busy || m.monthlyActive ? null : () => onBuy(AdFreePlan.monthly),
                  ),
                  const SizedBox(height: 10),
                  _PlanTile(
                    plan: AdFreePlan.lifetime,
                    price: m.priceOf(AdFreePlan.lifetime),
                    subtitle: 'One-time payment. Ads gone forever',
                    badge: 'BEST VALUE',
                    loading: buying == AdFreePlan.lifetime,
                    onTap: busy ? null : () => onBuy(AdFreePlan.lifetime),
                  ),
                ]),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: busy ? null : onRestore,
          icon: const Icon(Icons.restore_rounded, size: 18, color: AppColors.textDim),
          label: Text('Restore Purchases', style: AppText.body.copyWith(color: AppColors.textDim)),
        ),
      ]),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.price,
    required this.subtitle,
    required this.loading,
    this.onTap,
    this.badge,
    this.owned = false,
  });
  final AdFreePlan plan;
  final String price;
  final String subtitle;
  final bool loading;
  final bool owned;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = badge != null;
    return Semantics(
      button: onTap != null,
      label: '${plan.title}, $price',
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highlight ? AppColors.brand.withOpacity(0.14) : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: owned ? AppColors.success : (highlight ? AppColors.brand : AppColors.stroke),
              width: highlight || owned ? 1.6 : 1,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(plan.title, style: AppText.heading.copyWith(fontSize: 16))),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.star.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text(badge!, style: AppText.label.copyWith(color: AppColors.star, fontSize: 9.5)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(subtitle, style: AppText.bodyDim.copyWith(fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
              child: loading
                  ? const SizedBox(key: ValueKey('l'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : owned
                      ? const Icon(Icons.check_circle_rounded, key: ValueKey('o'), color: AppColors.success)
                      : Text(price, key: const ValueKey('p'), style: AppText.number.copyWith(fontSize: 17)),
            ),
          ]),
        ),
      ),
    );
  }
}
