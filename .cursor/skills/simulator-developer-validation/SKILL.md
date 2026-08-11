---
name: simulator-developer-validation
description: Launch and exercise Atlasbound’s Debug build in the iOS Simulator, including the opt-in Developer tools and local unlocks. Use when validating the playable app UI, checking developer-mode access, or confirming an unlock affects gameplay without cloud writes.
---

# Atlasbound Simulator Developer Validation

Run this workflow only against a Debug simulator build. Do not test unlocks while signed in: the screen deliberately disables them to prevent test data from syncing.

## Launch

1. Select an available iPhone simulator with `xcrun simctl list devices available` and boot it.
2. Build `Atlasbound` for that simulator in Debug, install the resulting `Atlasbound.app`, and launch it with `SIMCTL_CHILD_ATLASBOUND_ENABLE_DEVELOPER_MODE=true`. This process environment flag takes precedence over the bundled `.env` file and avoids changing a developer’s local configuration.
3. Operate the Simulator UI with Computer Use. Do not treat a successful `xcodebuild test` as a substitute for the interactive pass.

## Required interactive pass

1. Enter Guest mode if the welcome screen appears.
2. Open the map settings (gear), verify the **Developer** section and **Open developer tools** button are visible, then open it.
3. Confirm the screen shows **Unlock everything** plus its targeted unlock buttons. Tap **Unlock everything**.
4. Verify the confirmation text **Local developer unlock complete.**
5. Open Workshop → Decks and verify the unlocked card collection is present. If available, begin a Guardian training match and make one legal card play to verify that unlocked cards can enter gameplay.
6. Capture the accessibility text or screenshot for the Settings, Developer tools, and post-unlock state. Report the precise visible result, not merely that a command returned success.

## Safety and cleanup

- Keep the test in Guest mode. If an account is signed in, verify the unlock controls are disabled and the sign-out warning is visible; do not work around it.
- Do not grant or accept location permissions merely for this flow. The developer unlock seeds the local atlas without GPS.
- Test data is confined to the simulator app container. Only uninstall/reset that specific simulator app if a clean guest state is needed.

## Complementary checks

Run the focused unit tests for developer unlock and card state, then `./scripts/validate-pr.sh`. These support the Simulator result; they do not replace it.
