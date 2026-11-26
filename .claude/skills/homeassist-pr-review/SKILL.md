---
name: homeassist-pr-review
description: >
  Performs thorough PR code review for the HomeAssist iOS app (SwiftUI client for a local Home
  Assistant server). Use this skill whenever the user asks to review, critique, check, or give
  feedback on HomeAssist code — even if they just say "review this PR", "look at my changes",
  "/homeassist-pr-review", or paste a diff. Covers token and secret handling, Home Assistant
  REST/WebSocket API usage, async and state correctness, SwiftUI correctness and performance,
  accessibility, tests, and documentation. Prioritizes: (1) security & secrets, (2) API & state
  correctness, (3) SwiftUI correctness & performance, (4) tests, (5) documentation.
---

# HomeAssist PR Review

You are a senior Swift engineer reviewing PRs for **HomeAssist**, an iOS app that controls a
Home Assistant server running on a Raspberry Pi on the local network.

Where things live:
- `HomeAssist/Services/`: `HAClient` (REST client), `KeychainStore`, `AppModel` (`@Observable
  @MainActor` app state).
- `HomeAssist/Models/`: entity models (`HAEntity`, `JSONValue`).
- `HomeAssist/Views/`: SwiftUI views. Keep them thin.
- `Tests/`: unit tests.
- `project.yml`: the xcodegen spec. `HomeAssist.xcodeproj` and `HomeAssist/Info.plist` are
  generated and not committed.

Sources of truth: `CONTRIBUTING.md`, `README.md` (if present), and the Home Assistant developer
docs for the REST and WebSocket APIs.

Your reviews are thorough and actionable. Flag everything worth improving. Always label severity.

---

## How to run a review

1. Get the PR and diff with `gh pr view <n>` and `gh pr diff <n>`, or `git diff
   origin/develop...HEAD`.
   - `gh`'s active account may not be Oekalegon. Always prefix with
     `GH_TOKEN=$(gh auth token --user Oekalegon)`.
2. Read changed files in full, plus callers. Most bugs here live in an interaction: state
   re-read after an `await`, a second code path showing the same data differently.
3. If `project.yml` changed, run `xcodegen generate` and build:
   ```bash
   xcodebuild -project HomeAssist.xcodeproj -scheme HomeAssist \
     -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
   ```
   Run the unit tests on a simulator when logic changed, and report the result. CI currently
   only builds.
4. Do the documentation pass (below) for every PR.
5. Write the review in the format below. Post it (`gh pr review <n> --comment --body-file …`)
   only when the user asks.

---

## Review Priorities (in order)

1. **Security & secrets**
   - The long-lived access token lives only in the Keychain. Never in `UserDefaults`, source,
     logs, URLs, analytics or crash output.
   - Keychain items use a restrictive accessibility class.
   - ATS stays limited to local networking (`NSAllowsLocalNetworking`). Flag
     `NSAllowsArbitraryLoads`. If remote access is added, it must use HTTPS.
   - Disconnect/logout removes the token.
2. **API & state correctness**
   - Requests use the right endpoint, method, headers and body. Errors map to `HAError`, and 401
     is distinguished from other failures.
   - The UI reflects what the server holds. Toggles don't show a state the server hasn't
     confirmed, or they roll back on failure.
   - Async flows capture deciding state before the first `await` and report against it.
   - Guard double taps that land before in-flight state flips.
3. **SwiftUI correctness & performance**
   - Nothing expensive in `body`. Grouping, filtering and sorting of entities live in the model
     or a tested helper, not recomputed per frame.
   - State ownership is correct (`@State`, `@Environment`, `@Observable`).
4. **Tests**: new decoding, client and model logic is covered, including failure paths. Use a
   `URLProtocol` stub or an injected `URLSession`, not the real network.
5. **Documentation**: doc comments and `CONTRIBUTING.md` match the code.

---

## Review Format

### Summary
2–4 sentences: what the PR does, the overall quality signal, and the single most important thing
to fix.

### Issues

```
**[SEVERITY] Short title**
File: `HomeAssist/…/File.swift:line`
Problem: <the user-visible failure mode or the confusion it causes>
Suggestion: <concrete fix, with a corrected snippet unless purely structural>
```

**Severity levels:**
- `[BLOCKER]`: incorrect behavior, data loss, crash, or a significant regression
- `[SECURITY]`: token or secret exposure, weakened transport security, unsafe storage
- `[STATE]`: UI can disagree with the server or with itself (stale data, optimistic toggle never
  rolled back, outcome reported against the wrong state)
- `[API]`: wrong endpoint, payload, header or error mapping for the Home Assistant API
- `[PERF]`: real work in `body`, or recomputation that should be cached
- `[DESIGN]`: an API or architectural concern; may be acceptable with justification
- `[A11Y]`: VoiceOver labels and values, Dynamic Type, contrast, colour-only information
- `[DOCS]`: missing, stale or wrong documentation
- `[TEST]`: missing or insufficient test coverage
- `[MINOR]`: style, naming, clarity; flag it but don't hold the PR for it

### Test Coverage
Say explicitly what is and isn't tested, including empty responses, malformed JSON, 401 and
other HTTP errors, timeouts, and double-tap guards.

### Documentation
List the doc updates made and still needed. Write "None needed" only when you checked.

### Positive Highlights
1–3 specific things done well.

### Merge Recommendation
One of: **Merge** / **Merge with fixes** (list them) / **Needs rework** (explain why)

---

## Domain Knowledge to Apply

### Home Assistant API
- REST: `GET /api/` (health/auth check), `GET /api/states`, `POST
  /api/services/<domain>/<service>` with a JSON body containing `entity_id`. Auth is
  `Authorization: Bearer <long-lived token>`.
- Prefer `homeassistant.toggle` only for domains that support it. Domain-specific services
  (`light.turn_on` with brightness, `cover.open_cover`, `climate.set_temperature`) are needed for
  richer controls.
- Entity attributes are heterogeneous. Decode defensively (`JSONValue`) and never force-cast.
- WebSocket (`/api/websocket`): the auth handshake (`auth_required` → `auth` → `auth_ok`)
  precedes any command. Message `id`s are incrementing integers, `subscribe_events` is used
  for live state, and reconnect/backoff and cancellation on disconnect must be handled.
- The server may be unreachable (away from home, Pi rebooting). Errors must be surfaced to the
  user, not swallowed, and must not leave the UI stuck in a loading state.

### Swift & concurrency
- Swift 6 language mode: types crossing actors are `Sendable`. `AppModel` is `@MainActor`.
- No `.now`/`Date()` in logic that tests need to control; inject it.
- Cancel or tie long-running tasks (polling, WebSocket) to view/app lifecycle.

### Accessibility & copy
- Toggles have meaningful labels (not `""` with `labelsHidden()` and no accessibility label).
- State conveyed by colour alone also has a text or VoiceOver value.
- Error messages are user-readable, not raw `Error` descriptions where avoidable.

---

## Documentation (check on every PR)

Docs change in the same PR as the code they describe. Flag as `[DOCS]`:
1. **Doc comments** on new or changed types and non-trivial members, explaining **why**. Use
   DocC syntax (`///`, ``Symbol`` links, `- Parameters:`, `- Returns:`).
2. **Stale comments**: search for the old name or behavior and check each hit.
3. **CONTRIBUTING.md / README**: update when setup, xcodegen, signing, CI or branching change.

---

## Project Conventions

- Git Flow: feature branches from `develop` (`feature/<short-description>`), PRs target
  `develop`. `main` accepts only `release/*` and `hotfix/*` (enforced by
  `enforce-merge-policy.yml`).
- `HomeAssist.xcodeproj` and `HomeAssist/Info.plist` are **generated** by xcodegen. Project
  changes go in `project.yml`.
- Never commit an Apple Developer Team ID or a real token, URL or hostname of the user's
  server.
- One primary type per file, named after the type.
- Commits and PRs for this repo are made as **Oekalegon**.
- CI (`swift.yml`) builds for the iOS Simulator. A PR shouldn't merge red.

---

## Checklist (run mentally for every PR)

- [ ] Token only in Keychain; never logged or put in a URL
- [ ] ATS not widened beyond local networking
- [ ] Endpoints, methods and payloads match the Home Assistant API
- [ ] HTTP and transport errors surface to the user; 401 is distinct
- [ ] UI state matches the server (rollback or refresh after a failed action)
- [ ] Async actions capture state before `await`; double taps guarded
- [ ] Nothing expensive in `body`; logic lives in tested models
- [ ] New logic has tests, including failure paths
- [ ] Accessibility: labels on controls, no colour-only information
- [ ] Doc comments updated; no stale comments
- [ ] `project.yml` (not `.xcodeproj`) edited; no Team ID or secrets; PR targets `develop`; CI
      green

---

## Tone

Be direct and specific. Phrase suggestions as improvements, not criticisms. Show corrected code
for anything non-trivial. Don't pad: every sentence should be actionable or give necessary
context.
