# Transi

Public transit app for Bratislava. The main product is the iOS app; the repository also ships a watchOS companion and a Live Activity/Dynamic Island extension.

## Instruction source

- `AGENTS.md` is the single source of truth for repository guidance.
- `CLAUDE.md` must point to this file. Do not maintain a second copy of these rules.
- Repo workflows live under `.agents/skills/`; use the matching skill instead of reproducing its process here.

## Existing design

- Swift 5 with a SwiftUI/UIKit hybrid. `Transi/ContentView.swift` owns the `UITabBarController`; feature screens are mostly SwiftUI.
- Keep the existing `GlobalController` static service-locator pattern unless a task explicitly asks for an architectural change.
- Controllers and providers are shared `ObservableObject` singletons. Views normally hold them with `@StateObject`.
- Reuse the typed request helpers in `Shared/Util/Fetch.swift`. Existing APIs use completion handlers; do not introduce a parallel networking abstraction or migrate unrelated code to async/await.
- Keep persisted setting keys in `Shared/Models/Stored.swift`, pair new settings with defaults in `GlobalController.registerUserDefaults()`, and use `@AppStorage` in SwiftUI where that is the local pattern.
- Heavy parsing, routing, database, and network work stays off the main thread. Publish UI-observed state on the main thread and preserve existing queue/locking invariants.
- Reuse existing models, extensions, views, icons, and installed Swift packages before adding code or dependencies. Ask before adding a production dependency.
- Preserve the callback/event flows for Socket.IO (`cack`, `tabs`, `vInfo`), regional departures, session tokens, offline timetable data, deep links, and Live Activities when touching adjacent code.

## Platform policy

- Design and runtime quality target the newest installed iOS runtime, currently iOS 26.x. Prefer native current-platform components and Liquid Glass where it improves hierarchy or interaction.
- Keep the iOS 16.1 deployment target until explicitly changed. Gate iOS 26 APIs with availability checks and provide a correct, accessible fallback; older iOS may look simpler or do less work.
- The app, watchOS target, and Live Activity extension must keep building when shared code affects them. Give non-iOS targets focused design/runtime attention only when the request explicitly includes them.
- Preserve Dynamic Type, contrast, safe areas, touch targets, VoiceOver names for icon-only controls, reduce-motion behavior, and light/dark appearance. Do not add a new localization system during unrelated work; keep user-facing copy ready for localization.

## Working agreement

- Start with `git status`, branches, and worktrees. Preserve unrelated staged, unstaged, ignored, and generated files.
- Trace the real flow and every caller before changing shared code. Fix root causes at the narrowest shared point.
- For a new feature, use `$transi-feature`. For a reported defect, use `$transi-issue`. For review, use `$transi-review`. For simulator captures and the evidence site, use `$transi-visual-proof`.
- Keep diffs narrow. Do not opportunistically rewrite the architecture, reformat unrelated code, bump versions, publish releases, push, or merge unless requested.

## Verification

- The minimum build check for the iOS app is:

  ```bash
  xcodebuild -project Transi.xcodeproj -scheme Transi -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  ```

- Run the narrowest meaningful regression check for changed logic, then the affected scheme build. This repository currently has no active test target, so add only a small, maintainable test seam or harness when non-trivial logic needs one; do not scaffold a test architecture for trivial UI wiring.
- Build the watch or Live Activity scheme when the change touches its files, target membership, shared models, or shared controllers.
- Run `git diff --check` before handoff.
- Runtime verification uses a dedicated simulator on the newest installed iOS runtime described above. Use `xcrun simctl` and the installed iOS build/debug tooling; never open or focus Xcode or Simulator. The workflow must continue while the Mac is locked.
- When availability-gated or fallback code changes, also build and smoke the affected path on the oldest installed compatible iOS runtime. Do not require that extra runtime for changes that cannot affect the fallback.
- A successful build is not runtime proof. Exercise the changed behavior, inspect logs/state when relevant, and capture visual evidence for user-visible changes.

## Visual evidence and sharing

- Store proof under the ignored `.artifacts/transi/<date>-<slug>/` path and use `$transi-visual-proof` to capture and present it.
- When sharing any local-only page or artifact, expose only that artifact directory through Tailscale Serve and provide both local and Tailnet URLs. Never expose the repository root, API keys, build configuration secrets, or unrelated files.
