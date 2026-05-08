---
layout: default
title: REmu App Store Listing
---

# REmu — App Store Connect Listing Reference

Copy-paste source for the App Store Connect submission form. Keep this
file in sync with the live listing whenever metadata changes.

> **Important.** No trademark word (Nintendo, PlayStation, Pokémon,
> Mario, Zelda, Sonic, etc.) appears anywhere in the listing. Apple's
> automated metadata scanner rejects trademarked product names.

---

## App Name (≤ 30 chars)

```
REmu — Retro Library
```

## Subtitle (≤ 30 chars)

```
Bring your own classics
```

## Promotional Text (≤ 170 chars)

```
Import your own legally-owned retro game files and play them in
landscape with on-screen controls or an MFi gamepad. Save anywhere
with save states.
```

## Description (≤ 4000 chars)

```
REmu is a clean, focused retro library for files you already own.

Import your own ROMs from the Files app, organize them in a tidy
library, and play them with smooth Metal-accelerated rendering,
on-screen touch controls, or any MFi-compatible gamepad. Built for
landscape, designed to feel modern.

WHAT'S INSIDE
 • A polished library that auto-detects the system from each file you
   import
 • Cover art pulled from the file when available, or matched against
   an open-source thumbnail database
 • Save states from the in-game menu — pause, save, resume any time
 • One built-in original mini-game (Glowchase) so the app is fun out
   of the box
 • Full MFi controller support including DualSense and Xbox Wireless

WHAT'S NOT INSIDE
 • No game files. REmu does not ship, distribute, or download
   commercial games.
 • No BIOS files. Provide your own where required.
 • No ads, no in-app purchases, no tracking, no accounts.

YOUR RESPONSIBILITY
By using REmu, you confirm that any file you import is one you legally
own (typically dumped from your own cartridge or disc) or one that is
freely licensed (homebrew, public domain, etc.). Piracy is not
supported in any form.

PRIVACY
REmu stores everything on your device. Nothing is uploaded. See the
in-app Terms and Privacy Policy for full details.

REmu is an independent project and is not affiliated with, endorsed
by, or sponsored by any console manufacturer. All trademarks are the
property of their respective owners.
```

## Keywords (≤ 100 chars, comma-separated, **no trademarks**)

```
retro,emulator,save state,gamepad,landscape,classic games,homebrew,MFi,DualSense,library
```

## Category

- **Primary:** Entertainment
- **Secondary:** Utilities

## Age Rating

- **9+**
  - Cartoon or Fantasy Violence: **Infrequent / Mild** (Glowchase
    game-over animation only)
  - Realistic Violence: None
  - Sexual Content / Nudity: None
  - Profanity / Crude Humor: None
  - Alcohol / Tobacco / Drugs: None
  - Mature / Suggestive Themes: None
  - Horror / Fear Themes: None
  - Gambling / Contests: None
  - Unrestricted Web Access: None
  - Medical / Treatment Information: None

## Support URL

```
https://fatih-koca.github.io/REmu/
```

## Marketing URL

```
https://fatih-koca.github.io/REmu/
```

## Privacy Policy URL

```
https://fatih-koca.github.io/REmu/privacy.html
```

## Terms of Use URL

```
https://fatih-koca.github.io/REmu/terms.html
```

## Pricing

- **Free**, no in-app purchases.

## Privacy Disclosure (App Store Connect privacy questionnaire)

- **Do you collect data?** **No.**
- **Do you track users?** **No.**
- All categories: zero items.

## Review Notes (private — for the App Review team)

```
This app does not include or distribute any commercial ROM files,
BIOS files, or copyrighted artwork. Users import their own
legally-owned ROM files via the iOS Files app.

The app contains one original built-in mini-game (Glowchase) with no
third-party content. Reviewers can verify functionality with the
built-in Glowchase demo from the home screen — no test ROMs are
provided, in line with Apple Guideline 4.7.

Per Apple Guideline 4.7, retro game console emulators are permitted;
user-imported content is the user's responsibility, surfaced clearly
via a first-launch acceptance gate (EULA).

Network usage: a single optional cover-art lookup hits
raw.githubusercontent.com (libretro-thumbnails open-source project).
The lookup is OFF by default and must be enabled in Settings; when
enabled it sends only the ROM filename, no user identifier, no
analytics, no ad-network calls. Disclosed in the in-app Privacy
Policy.

The app is independent and not affiliated with any console
manufacturer.

Contact: fatihkcf@gmail.com
```

## Screenshots Checklist

Required orientations: **landscape** (the app is landscape-locked).

Required device classes:

- [ ] 6.7" iPhone (e.g. iPhone 15 Pro Max) — landscape
- [ ] 6.5" iPhone (e.g. iPhone 11 Pro Max) — landscape (optional but
      recommended)
- [ ] 12.9" iPad Pro — landscape
- [ ] 11" iPad Pro — landscape (optional but recommended)

Suggested shots (5–6 total):

1. Empty library / first-run state
2. Library with **homebrew or public-domain** covers — never any
   commercial cover art (no Pokémon, Mario, Zelda, etc.)
3. Glowchase mini-game in play
4. In-game emulator screen with on-screen gamepad overlay (use a
   public-domain demo ROM)
5. Splash screen with floating retro glyphs
6. EULA / first-launch acceptance gate (proves the IP gate exists)

## Submission Pre-Flight Checklist

- [ ] Build uploaded to App Store Connect via Xcode → Archive → Validate → Distribute
- [ ] PrivacyInfo.xcprivacy verified inside the bundle
- [ ] Privacy Policy URL returns 200
- [ ] Terms of Use URL returns 200
- [ ] App icon does not resemble any console silhouette / button layout
- [ ] No copyrighted box art or trademark words in screenshots
- [ ] First-launch EULA gate triggers on a clean install
- [ ] Glowchase plays without any imported ROM
- [ ] Online cover-art lookup defaults to OFF
- [ ] Review notes pasted into App Store Connect
