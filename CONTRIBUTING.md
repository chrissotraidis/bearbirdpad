# Contributing to BanjoPad

Thanks for helping make the iPhone and iPad port better.

## Before opening an issue

- Search existing issues first.
- Reproduce the problem on the latest `main` build when practical.
- Include the BanjoPad commit, Apple device model, OS version, install method,
  input method, and exact reproduction steps.
- Attach logs or screenshots only after checking that they contain no personal
  paths, signing information, ROM data, saves, or generated game material.
- Never request, attach, or link to copyrighted game data.

The structured bug-report template collects the details needed to distinguish
Simulator, physical-device, touch, controller, lifecycle, and signing issues.

## Making a change

1. Run `scripts/check-repo-safety.sh`.
2. Keep changes in this repository. `sources/` contains disposable, fetched
   upstream inputs.
3. Edit maintained patches or BanjoPad-owned iOS/scripts/docs rather than
   committing a generated upstream tree.
4. Run the focused validation for the change:

   ```sh
   scripts/test-touch-input.sh
   scripts/build-ios.sh --simulator --app --config Release
   ```

5. Re-run `scripts/check-repo-safety.sh` and update documentation when
   observed behavior or a release gate changes.

Pull requests should stay focused and explain the user-visible impact,
validation performed, and physical-device checks that remain open.

## Game-data boundary

ROMs, generated recompilation inputs, saves, texture packs, device backups,
signed applications, provisioning profiles, and IPAs must never enter Git
history. Keep legal local game data under ignored `ref/` or inside an installed
app's Documents container.

## Licensing

Each upstream component retains its own license and copyright. BanjoRecomp is
distributed under GNU GPL version 3; other dependencies carry their own terms.
See [`RIGHTS_AND_LICENSES.md`](RIGHTS_AND_LICENSES.md) before proposing binary
distribution.
