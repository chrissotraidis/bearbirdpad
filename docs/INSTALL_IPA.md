# Install the BearBirdPad developer preview

The BearBirdPad download is an unsigned developer-preview IPA. It is not an
App Store or TestFlight build. A sideloading tool must sign it with your Apple
ID for your own iPhone or iPad.

The IPA contains no ROM, save, extracted game assets, provisioning profile, or
maintainer certificate. You must provide your own legally acquired
Banjo-Kazooie NTSC-U 1.0 ROM after installation.

[Download BearBirdPad 0.1.0 Preview 2](https://github.com/chrissotraidis/bearbirdpad/releases/download/v0.1.0-preview.2/BearBirdPad-0.1.0-preview.2-unsigned.ipa)

The GitHub release page records the SHA-256 for the exact published asset.

## Install

1. Install a personal-signing tool such as AltStore Classic by following its
   official [macOS](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)
   or [Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
   guide.
2. On iOS or iPadOS 16 and later, enable **Settings → Privacy & Security →
   Developer Mode** if your signing workflow requires it.
3. Download the BearBirdPad `-unsigned.ipa` and save it to Files.
4. In AltStore Classic, open **My Apps**, tap **+**, select the IPA, and let
   AltStore sign and install it.
5. Launch BearBirdPad and import your own supported ROM through Files.

Your Apple ID credentials are handled by the signing tool and Apple, not by
BearBirdPad. Consult the tool's current documentation before signing.

## Refresh and update

Personal signatures can expire and may need periodic refresh. To update
BearBirdPad, install the newer IPA over the existing app with the same Apple ID
and signing tool. Do not delete the old app first: deletion removes its app
container, including the stored ROM, saves, settings, and touch layouts.

Back up `Documents/BanjoRecompiled/saves/` before updating or changing signing
identities. Sideload tools can still replace an app container, so preservation
outside BearBirdPad's tested in-place update path cannot be guaranteed.

## Preview limitations

- This is early test software and may contain bugs.
- The published IPA must be re-signed by the installer.
- No jailbreak or JIT entitlement is required by BearBirdPad.
- Automated controller sleep/disconnect/reconnect coverage is included, but
  physical Bluetooth, wired, natural-sleep, mapping, and two-controller
  acceptance remain incomplete.
- App Store, TestFlight, and official third-party-store distribution are not
  part of this preview.
