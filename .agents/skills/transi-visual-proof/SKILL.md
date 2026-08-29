---
name: transi-visual-proof
description: Verify Transi UI headlessly on iOS Simulator, capture screenshots or recordings, build an HTML evidence page, and publish only that page through Tailnet. Use after user-visible feature or issue work, or when visual/runtime proof is requested.
---

# Transi Visual Proof

Produce proof that shows the requested behavior, not merely that the app launched.

## Run without stealing focus

- Pin verification to a dedicated simulator named for Transi on the newest installed iOS runtime. Reuse its UDID; if it does not exist, create it with `xcrun simctl create` using the current iPhone Pro device type and runtime. Never borrow an arbitrary booted simulator.
- Boot the pinned UDID headlessly with `xcrun simctl boot` and wait with `xcrun simctl bootstatus`. Never run `open`, `xed`, `open_sim`, or `build_run_sim`, because those can foreground Simulator.
- For the default iOS flow, verify/set XcodeBuildMCP session defaults for `Transi.xcodeproj`, scheme `Transi`, and the pinned UDID; then use `build_sim`, `get_sim_app_path`, `install_app_sim`, and `launch_app_sim`. Fall back to `xcodebuild` plus `simctl install`/`launch` when those tools are unavailable.
- When watchOS is explicitly in scope, use the affected watch scheme and a dedicated compatible paired iPhone/Watch simulator on the newest installed watchOS runtime. When the Live Activity extension is explicitly in scope, build its scheme and prove it through the host iOS simulator. If the required runtime is not installed, complete available builds and report runtime proof as an unverified-platform blocker.
- Use `snapshot_ui`/`wait_for_ui` before semantic `tap`, `swipe`, or `type_text` operations. Re-snapshot after navigation or layout changes. Use XcodeBuildMCP's launch log path or `xcrun simctl spawn <UDID> log stream` for logs; use XcodeBuildMCP capture tools or `simctl io` for screenshots and video.
- Use the simulator-browser workflow only when a live browser mirror materially helps; pin it to the exact simulator and stop its helper when finished.

## Capture proportional evidence

- A stable one-screen change: capture clear screenshots of every changed state.
- Navigation, gestures, animation, loading transitions, multi-step features, or a reproduced defect: record the full interaction and also capture key screenshots.
- Include happy path plus material loading, empty, error, permission, offline, background, light/dark, Dynamic Type, or reduced-motion states affected by the change.
- Use descriptive media names. Do not include notifications, credentials, API keys, personal location/history, or unrelated desktop content.

## Build the evidence page

Create `.artifacts/transi/<date>-<slug>/index.html` with plain self-contained HTML/CSS and relative media paths. No framework, package, CDN, analytics, or build step.

The page must contain:

- feature/issue name, branch/commit, simulator device and iOS version;
- acceptance criteria and short steps showing how each changed behavior works now;
- screenshots and videos grouped by feature/state, with useful captions and native video controls;
- focused checks and scheme build results;
- known limits or unverified non-primary platforms.

Open the page in the in-app browser and verify layout, every image, and video playback before sharing it.

## Share on Tailnet

Inspect `tailscale status` and existing Serve routes first. Publish only the absolute evidence directory at a unique path, for example:

```bash
tailscale serve --bg --set-path /transi/<unique-slug> /absolute/path/to/.artifacts/transi/<date>-<slug>
```

Read the actual URL from Tailscale Serve status and verify the page and media return successfully through that URL. Keep the route available for the user; replace or remove it only when asked or superseded. If Tailscale is unavailable or unauthenticated, report that exact blocker and do not claim the local page is shared.

Return the artifact directory, `index.html`, local URL, Tailnet URL, captured scenarios, and any state that could not be demonstrated.
