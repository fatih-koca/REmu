---
layout: default
title: REmu Privacy Policy
---

# REmu — Privacy Policy

**Last updated:** May 7, 2026

REmu is built to respect your privacy. This document describes what data the app handles and what it does not.

---

## No Personal Data Collected

REmu does not collect, store, or transmit any personally identifiable information. We do not require an account, and we do not log your activity.

## Local-Only Storage

All ROM files, save states, screenshots, and game cover art remain on your device, inside the app's protected sandbox. They are never uploaded to any server, shared with us, or made available to third parties.

## No Analytics or Tracking

This version of REmu does not include any analytics SDK, tracking pixel, advertising network, or third-party telemetry. Crash reports, if shared, are handled by Apple's standard system tooling and require your explicit opt-in via iOS Settings.

## Network Activity

REmu makes outbound network requests in only one circumstance:

- **Game cover art lookup.** When you import a ROM whose cover image is not already embedded in the file, REmu may request a public box-art image from the open-source [libretro-thumbnails](https://github.com/libretro-thumbnails) project on GitHub. The request:
  - is sent over HTTPS to `raw.githubusercontent.com`,
  - contains no user identifier, no device identifier, and no analytics payload,
  - sends only the ROM filename you imported as part of the URL path,
  - is read-only — no data is uploaded, only the public image is fetched and saved locally.

If a matching image is not found, no further requests are made for that ROM. This lookup is convenience-only; the app remains fully usable offline (a generic console icon is shown instead).

## Advertising

The current version of REmu does not display advertisements and contains no in-app purchases. If a future release introduces ad-supported features, this policy will be updated and consent will be requested where required (e.g., via App Tracking Transparency).

## External Links

The in-app tutorial may reference public websites such as itch.io for legal homebrew games. Following an external link takes you to the third party's own privacy environment, which is governed by their policies, not this one.

## Children's Privacy

REmu is not directed at children under 13 and does not knowingly collect data from anyone. If you believe a child has provided personal data through this app, please contact us so we can confirm there is nothing on our end to remove.

## Your Rights

Because REmu does not collect any personal data, there is no user data on our servers to access, correct, export, or delete. Removing the app from your device deletes all associated content, including imported ROMs, save states, and cover art.

## Contact

For privacy questions, please contact: **fatihkcf@gmail.com**

## Changes

We may revise this policy. The "Last updated" date above reflects the most recent revision. Material changes will be announced in app release notes.
