# Color Gravity

A 2D Android arcade game built with Flutter.
**Color decides _what_ can interact. Gravity decides _where_ things move. Master both at the same time.**

You steer a glowing orb up an endless tower. Swipe to shift gravity in any of four directions, drag to steer, and match your color to collect orbs, pass gates and survive hazards. Same-colored orbs that gravity pushes together **combine** into bigger, more valuable orbs.

## Features
- **Gravity system** — 4 directions, smooth/instant transitions, gravity switches, zones, gates, locks, reversing and rotating gravity.
- **Color system** — 5 base colors (+ cyan in late worlds), each with a unique **shape** for accessibility; color gates, barriers, multi-color and color+gravity gates, colored hazards, color bands/rings.
- **Merge & chains** — gravity-driven merging, merge zones, chain combos, perfect actions.
- **1000 levels across 10 worlds** — generated from data (`LevelConfig` + reusable segments), validated for fairness, deterministic per level.
- **Difficulty tiers** — Easy (1–120) → Medium (121–400) → Hard (401–700) → Very Hard (701–1000), with a challenge level every 10 levels followed by a breather.
- **Modes** — interactive tutorial, Daily Challenge (modifiers + streaks), Endless.
- **Progression** — stars, coins, 16 achievements, 19 cosmetics (skins, trails, gravity FX, merge FX). Cosmetics are visual only.
- **Monetization** — AdMob (interstitial at natural breaks only, opt-in rewarded, Level Map banner) and Google Play Billing **Ads-Free** plans: **1 Month (₹299, subscription)** and **Lifetime (₹2,999, one-time)**.
- **Offline-first** — all progress stored locally with versioned, corruption-safe saves.
- **Original assets** — audio is synthesized by `tool/gen_audio.py`; icons by `tool/gen_icons.py`; font is Inter (SIL OFL, `assets/fonts/OFL.txt`).

## Project layout
```
lib/
  core/        theme, constants (AppConfig), models (GameColor, GravityDir)
  game/        engine, entities, systems (gravity, color, scoring, objectives), collision, effects, render
  levels/      models (LevelConfig, tiers, objectives), segments, generators, validation
  progression/ save data, progress controller, achievements, cosmetics
  services/    storage, settings, audio, haptics, ads, purchases, monetization
  screens/     splash, onboarding, home, level_map, gameplay, result, failure, daily, endless, cosmetics, achievements, settings
  widgets/     shared UI + animations
test/          unit + widget tests
tool/          asset generators (audio, icons)
```

## Run & test
```bash
flutter pub get
flutter test
flutter run
```

## Before publishing
1. **AdMob:** replace the Google test IDs in `lib/core/constants/app_config.dart` and the `APPLICATION_ID` in `android/app/src/main/AndroidManifest.xml`.
2. **Play Billing:** in Play Console create
   - subscription `ads_free_monthly` (1 month, ₹299)
   - in-app product `ads_free_lifetime` (one-time, ₹2,999)
3. **Signing:** create `android/key.properties`:
   ```
   storeFile=../upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
   then `flutter build appbundle --release`.
4. **Privacy policy:** https://api.buildprivacypolicy.com/policy/5e19d9a2-9943-4f01-a8ee-ff62e3d67f1f (opened from Settings → Privacy Policy; an offline copy is shown if there is no connection; `PRIVACY.md` mirrors it).
5. Store icon: `store/play_store_icon_512.png`.

Contact: aakashmangukiya10@gmail.com
