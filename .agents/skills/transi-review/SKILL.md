---
name: transi-review
description: Review Transi code changes for correctness, regressions, platform behavior, and missing proof. Use for local diffs, branches, commits, or pull requests; read-only unless the user also asks to fix findings.
---

# Transi Review

Review the requested change against its real base and the repository rules. Optimize for defects a user can hit, not stylistic preference.

## Establish the target

1. Inspect status, branches, worktrees, the requested base, and the complete diff. Do not assume `main` or a remote ref is current.
2. Read every changed file in context. Trace callers, shared models, persistence, networking, target membership, and UI state affected by the change.
3. Keep the review read-only unless fixes were explicitly requested.

## Review for

- Incorrect behavior, crashes, data loss, stale state, error paths, and regressions outside the named happy path.
- Main-thread violations, unsafe shared state, lifecycle/background behavior, cancellation, retain cycles, and races around controllers, queues, locks, timers, or Socket.IO callbacks.
- API/session failures, decoding drift, date/time-zone mistakes, online/offline parity, database consistency, and `UserDefaults` key/default mismatches.
- iOS 26 design and behavior, availability gates and correct iOS 16.1 fallback, target membership, watchOS/Live Activity compatibility when shared code changes.
- Accessibility, Dynamic Type, contrast, hit targets, light/dark mode, reduced motion, and user-facing failure/empty/loading states.
- Verification gaps: missing focused checks, untested reproduction, build gaps, or screenshots/recordings that do not prove the requested behavior.

Ignore cosmetic style differences that match nearby code. Do not request speculative abstractions, broad refactors, or new dependencies when a smaller correction works.

## Validate

Run focused checks that are safe and proportional to the diff. For user-visible behavior, inspect the supplied visual proof or reproduce it headlessly on the newest installed iOS simulator. When availability-gated or fallback code changes, require a build and smoke of that path on the oldest installed compatible iOS runtime too. A catalog entry, successful compile, or static screenshot of the wrong state is not proof.

## Report

List findings first in severity order:

- `[P0]` data loss, security, or app-unusable failure.
- `[P1]` common crash or major broken behavior.
- `[P2]` real but narrower correctness, compatibility, performance, or accessibility defect.

Each finding must name a precise file/line, triggering scenario, user impact, and the smallest safe correction. If there are no actionable findings, say `No actionable findings.` Then state what was validated and any residual risk or unverified platform. Do not turn optional polish into a blocking finding.
