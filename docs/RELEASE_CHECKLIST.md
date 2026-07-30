# BearBirdPad release checklist

This is the final gate for a public source snapshot or downloadable IPA.

## Every public source update

- [ ] `scripts/check-repo-safety.sh` passes.
- [ ] Pinned source revisions replay every maintained patch without manual
      edits.
- [ ] `scripts/test-touch-input.sh` passes for touch-related changes.
- [ ] The relevant Simulator and device Release targets build.
- [ ] `scripts/package-audit.sh` accepts the intended app.
- [ ] README setup steps and screenshots match the current interface.
- [ ] No ROM, save, texture pack, generated source, device backup, signing
      material, signed app, or IPA appears in the current tree or Git history.
- [ ] Remaining physical-device limitations are stated plainly.
- [ ] [`LICENSE`](../LICENSE), [`RIGHTS_AND_LICENSES.md`](../RIGHTS_AND_LICENSES.md),
      and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) match the exact
      source pins and distribution scope.

## Before publishing an unsigned developer-preview IPA

- [ ] [`RIGHTS_AND_LICENSES.md`](../RIGHTS_AND_LICENSES.md) still states the
      game-data boundary and does not claim to relicense third-party projects.
- [ ] RecompFrontend has an explicit, authoritative project license compatible
      with the intended distribution. Until then, binary publication is
      blocked.
- [ ] Review the exact package and distribution plan for GPLv3
      corresponding-source and third-party notice obligations.
- [ ] Publish or otherwise provide the complete corresponding source for the
      exact binary, including BearBirdPad patches and build scripts; do not rely
      solely on mutable upstream links.
- [ ] Build from a clean checkout at a deliberate tag.
- [ ] Set a stable bundle identifier, app version, and monotonically
      increasing build number.
- [ ] Run `scripts/package-ios.sh` and record the exact SHA-256.
- [ ] Confirm the IPA contains no ROM, save, texture pack, generated source,
      provisioning profile, maintainer certificate, or device backup.
- [ ] Re-sign and update-install the exact IPA on physical iPhone and iPad.
- [ ] Confirm that update installation preserves the existing ROM, save,
      configuration, and the separate phone/tablet touch-layout profiles.
- [ ] Replay launch, Files import, touch controls, menu access, gameplay,
      background/foreground, force-quit/relaunch, and save reload.
- [ ] Record the tag, commit, Xcode/SDK versions, supported device/OS range,
      package SHA-256, validation matrix, and known limitations in release
      notes.
- [ ] Publish as a clearly labeled developer preview, not as an App Store or
      TestFlight release.

## Before publishing a maintainer-signed build

- [ ] Use a deliberate distribution identity and fresh provisioning profile.
- [ ] `REQUIRE_SIGNED=1 scripts/package-audit.sh <app>` passes on the exact
      bundle.
- [ ] Install the packaged IPA on clean physical hardware and complete the
      lifecycle, audio-route, interruption, controller, and performance
      matrix.
- [ ] Record the signing type without publishing certificates, profiles, or
      other signing material.

## Current publication gates

- No public developer-preview IPA has been released.
- The regular physical iPhone/iPad play path is stable, but the wider
  controller reconnect/rumble, audio-route/interruption, and performance
  matrix is incomplete.
