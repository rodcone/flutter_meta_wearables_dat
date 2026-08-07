---
name: dat-update
description: Update this plugin to a new Meta Wearables DAT SDK release, end to end — changelog analysis, binary/dependency bump, API snapshot refresh, native + example-app implementation, verification, PR, and isolated review. Stops before merge and publish.
when_to_use: Only when the maintainer explicitly asks to update the DAT / Meta Wearables SDK to a named version, e.g. "/dat-update 0.10.0". Never infer this from a passing mention of a new release.
argument-hint: [dat-version]
disable-model-invocation: true
model: opus
effort: max
disallowed-tools: Bash(gh pr merge:*) Bash(git tag:*)
---

# DAT SDK update

Target DAT version: `$ARGUMENTS`.

Multi-hour job. Phases run in order. Everything mechanical lives in
[references/environment.md](references/environment.md) — read it before Phase 2.

## Standing rules — these apply on every turn, not just the first

The frontmatter above is **turn-scoped**: `disallowed-tools`, `model` and `effort` all lapse when
the maintainer sends their next message, and this job spans many turns. Only this prose persists.
So treat the following as standing instructions and re-check them each turn:

1. **Never merge. Never publish.** No `gh pr merge`. No `git tag`. No `dart pub publish` except
   `--dry-run`. Pushing a `v*` tag *is* the publish trigger and the maintainer does that themselves
   after hardware testing. If you find yourself about to run any of these, stop.
2. **Stay on a flagship model at max effort.** The frontmatter only guarantees this for turn one.
   If quality or context seems to have degraded mid-run, say so and ask the maintainer to set the
   session model rather than continuing quietly.
3. **Keep it a Flutter plugin.** A new SDK capability does not automatically deserve a Dart API —
   most don't. Smallest change that adopts the release correctly.
4. **Never trust the changelog alone.** Every API claim is verified against the shipped binary.
5. **Report honestly.** Failed builds and skipped steps go in the final report.
6. **Ask rather than assume.** Autonomy (Phase 4) means not asking permission for routine scope
   calls the standing rules already cover. It does **not** mean guessing. Interrupt whenever the
   right answer isn't obvious — an unexpected SDK behaviour, a build failure with more than one
   plausible cause, an API whose intent is unclear from the samples. A five-minute question beats
   an hour of work in the wrong direction.
   **Attach a confidence percentage to every option** you offer ("A — 75%, B — 20%, C — 5%").
   If one option is **≥90%**, don't ask: take it, state that you did, and continue.
7. **Record what surprised you** (Phase 11). Anything this skill failed to predict is a defect in
   the skill, not just an obstacle in the run.

## Standing scope rules

Applied every release unless the maintainer says otherwise:

- **Display glasses are out of scope** — `MWDATDisplay`, `DisplayAccess`, `ButtonGroup`, bitmap
  images, tap routing. This plugin is camera-only.
- **Don't mirror an SDK enum into Dart when an existing one covers it** (0.9.0's `CameraState`
  duplicates `StreamState` — deliberately unexposed).
- **Both packages move in lockstep** at the same plugin version.
- **Plugin version ≠ DAT version.** A DAT bump is a **minor** bump of the plugin (pre-1.0).

---

## Phase 0 — Preflight (blocking)

```bash
.claude/skills/dat-update/scripts/preflight.sh $ARGUMENTS
```

This validates the version string, refuses a dirty tree, fast-forwards both Meta clones, confirms
the iOS tag exists **and carries all three xcframeworks**, confirms all three Android Maven
artifacts are published, and confirms the four plugin-version locations agree. **If it exits
non-zero, stop and report — do not work around it.** Every check it makes is one that otherwise
surfaces hours later or after something has already been deleted.

Then: `git checkout -b dat-<version>`, and read `CLAUDE.md` (accurate as of the *previous* release)
plus `doc/MAINTAINERS.md`.

Anchor every path from here on: `ROOT="$(git rev-parse --show-toplevel)"`. The shell's cwd persists
between commands and later phases run `rm -rf`.

## Phase 1 — Intelligence gathering

1. **Changelogs**, both platforms, the `## <version>` section, in each clone's `CHANGELOG.md`.
2. **Meta's own skills** — updated per release, usually ahead of the prose docs:
   `git diff <prev>..<version> -- plugins/mwdat-{ios,android}/skills/` in each clone.
   `camera-streaming`, `session-lifecycle`, `dat-conventions` are relevant; skip `display-access`.
   They document the *native* API — a migration guide for our native code, **not** content to copy
   into our Dart-facing `agent/` skills.
3. **Sample apps** — `samples/CameraAccess` in both clones, diffed across the release. This is the
   answer when you're unsure how a new API is meant to be used. Sample-app *choices* are not SDK
   *constraints* — don't confuse the two.

Output: a table of every changelog item → relevant? → why → feasibility. Display items get one line.

## Phase 2 — Bump binaries and dependencies

**Extract to a temp dir and verify before deleting anything vendored.** Preflight confirmed the tag
carries all three, but the swap itself must still be ordered so a failure can't leave the repo with
no frameworks at all. See `references/environment.md` § "Swapping the xcframeworks safely" for the
exact sequence, then run `./scripts/thin-xcframeworks.sh`.

Android: bump `ext.mwdat_version` in **both** `android/build.gradle` files.

Re-check the iOS deployment floor — it moves without warning:
```bash
grep -ho 'target arm64-apple-ios[0-9.]*' "$ROOT"/ios/flutter_meta_wearables_dat/Frameworks/MWDATCamera.xcframework/ios-arm64/*/Modules/*.swiftmodule/*.swiftinterface | head -1
```
If it moved, that is consumer-breaking: six build files, the prose mentions in Phase 7, and a
prominent changelog entry.

## Phase 3 — Refresh API snapshots, diff the real surface

**This is what makes the plan trustworthy.**

1. Regenerate `doc/ios/{MWDATCore,MWDATCamera,MWDATMockDevice}.swift`. These are Xcode "Generated
   Interface" dumps — `.swiftinterface` merged with the `.swiftdoc` beside it — so they carry doc
   comments the raw interface lacks. Those comments are the point: they're where the SDK explains
   lifecycle and threading you cannot infer from signatures.

   `sourcekitten` drives the same SourceKit request Xcode uses. If it isn't installed, **ask before
   installing it** — `brew install` modifies the maintainer's machine and is not yours to decide.

   **Validate before overwriting.** Usable only if it contains doc comments, declares roughly the
   previous symbol count, and reads like the existing files. Compare against
   `git show HEAD:doc/ios/<file>`. If it fails, **discard and ask the maintainer** to paste from
   Xcode. Never silently fall back to the raw `.swiftinterface` — it looks fine and loses the value.

   Preserve the `// ⚠️ Reference snapshot…` headers. They are stripped every release and they are
   load-bearing.
2. **Diff the real surface**, old vs new, both platforms — the changelog is a lead, not evidence.
   iOS: previous snapshot vs new, plus the vendored `.swiftinterface` (the binary outranks both).
   Android: `javap` both AAR versions. Recipes in `references/environment.md`.
3. Grep every SDK symbol the plugin references and confirm each still exists.

## Phase 4 — Plan

Cover iOS, Android, example app, docs. Per item: the file, the change, and *why the SDK forces it*.
Flag every consumer-visible change. Keep the plan on disk — it feeds the PR description and report.

**Run autonomously from here** — in the sense of standing rule 6: don't seek approval for routine
scope calls, but don't guess either. For a scope decision the standing rules cover, take the
**conservative** option (smaller, no new Dart surface, defer over adopt) and record it for the
Phase 10 report with its alternative and cost.

Ask when the answer isn't obvious: an SDK behaviour neither the samples nor the interface explain,
a change whose blast radius you can't bound, two defensible designs with materially different
consequences for consumers. Give options with confidence percentages; act without asking at ≥90%.

## Phase 5 — Implement

iOS native → Android native → Dart (only if forced) → example app. Match surrounding style. Comment
the *why* for lifecycle and ordering constraints specifically — that is the knowledge that gets lost
between releases. Keep the example app simple; it is a demo.

## Phase 6 — Verify

Run the full matrix in `references/environment.md`. All of it.

**Capture the maintainer's Flutter SPM setting first and restore it at the end** — it is global
machine state, not repo state:
```bash
SPM_WAS=$(flutter config --list | sed -n 's/.*enable-swift-package-manager: *//p')
# ... run both resolver builds ...
[ "$SPM_WAS" = "true" ] && flutter config --enable-swift-package-manager \
                        || flutter config --no-enable-swift-package-manager
```
The SwiftPM build also rewrites two tracked files; the reference has the exact recovery.

## Phase 7 — Versions, changelogs, docs

1. Version → next minor in all four locations (preflight already proved they agreed).
2. **Both `CHANGELOG.md` files** need a `## <version>` entry — the release workflow extracts them.
   The mock entry is not boilerplate: 0.9.0 silently made mock devices enforce the same
   `Info.plist` checks as real hardware, a consumer-visible break that reached our own release
   notes only because review caught it.
3. **Docs sweep** — always the under-scoped step:
   - `README.md`, mock `README.md`, `llms.txt`
   - `lib/flutter_meta_wearables_dat.dart` — the dartdoc error-code list is the *published
     contract*; new and platform-only codes belong there
   - `AGENTS.md`, `agent/claude/`, `agent/cursor/`, `agent/github/` — installed into *consumer*
     repos by `install-skills.sh`, so staleness leaks outward
   - `CLAUDE.md`, `doc/MAINTAINERS.md`
   - install snippets pin `^<old>` — bump or consumers never resolve the release
   - sweep: `grep -rn "<old-version>\|<old-ios-floor>" --include='*.md' --include='*.mdc' --include='*.dart' .`

## Phase 8 — Pull request

Commit explaining *why* the SDK forced each change. Push the branch, open the PR (what changed per
platform, consumer-visible breaks, what was left out, how it was verified). Do not merge.

## Phase 9 — Isolated review

You wrote this code; you are the worst reviewer of it. Reviewing in this context inherits every
rationalization you already made.

**Spawn a subagent with fresh context** (Agent tool, `general-purpose`, flagship model) and have it
run the `plugin-pr-review` skill against the PR. Give it the PR number and the repo path — not your
reasoning. Then:

1. Apply findings that survive scrutiny; re-run the affected parts of Phase 6; push.
2. Re-review in a **new** subagent — never reuse the one that already reviewed.
3. Cap at **three rounds**. Anything still open goes in the report rather than looping.

Verify each finding against the shipped binary before accepting *or* dismissing it. On the 0.9.0
run this caught a real blocker plus a docs-contract gap, and also produced one confident-sounding
finding that was simply wrong — both outcomes are normal.

## Phase 10 — Hand-off

The maintainer tests on hardware before merging, so this is the deliverable. Post in chat:

- **What changed** — per platform, plus anything consumer-visible.
- **Manual test plan** — ordered on-device steps with expected results. Cover this release's
  specific regression risks and what only hardware can exercise (doff, power-off mid-stream,
  thermal, lock/unlock recovery, background streaming), plus a mock pass. State explicitly which
  steps the mock **cannot** stand in for.
- **Decisions I made for you** — every autonomous scope call, its alternative, and what that would
  have cost. Empty is a fine answer; silence is not.
- **Limitations** — what you couldn't verify, assumptions made, findings left open after three
  review rounds, follow-ups worth their own PR.
- **What I taught this skill** — the Phase 11 edits, one line each. "Nothing surprised me" is a
  valid and good answer.

Close by restating the release path: merge → tag `v<version>` from `main` → push the tag. Do not
run those.

## Phase 11 — Improve this skill

Every release teaches something. A DAT update happens roughly every five weeks, so a lesson dropped
here is a lesson re-learned the hard way in five weeks' time.

**Capture as you go.** The moment something surprises you — a step that failed, a command that
needed different flags, an ordering that mattered, a check that should have run earlier, guidance
here that turned out wrong — note it. Don't rely on remembering at the end of a multi-hour run.

**Then route each lesson to the narrowest place that fixes it:**

| The lesson is… | Goes in |
| --- | --- |
| a check that would have caught this earlier | `scripts/preflight.sh` |
| a command recipe, environment trap, or platform quirk | `references/environment.md` |
| a phase ordering, standing rule, or scope decision | `SKILL.md` |
| something about the *plugin's* architecture, not the update process | `CLAUDE.md` |
| a step a human doing this by hand also needs | `doc/MAINTAINERS.md` |

Prefer `preflight.sh` over prose wherever a lesson can be expressed as a check — an assertion that
fails loudly beats a paragraph the next run might skim past. Prefer `references/` over `SKILL.md`:
the body is re-sent every turn, so it is the expensive place to put anything.

**Rules for editing yourself:**

- **Only record what will recur.** A one-off upstream outage is not a lesson. "Meta moved the
  frameworks out of the tag tree" is.
- **Fix wrong guidance, don't append to it.** If a step here proved incorrect, correct it in place.
  Contradictory layers are worse than no guidance.
- **Stay small.** A lesson is usually one sentence, one table row, or one assertion.
- **Prune while you're here.** If something has been obsolete for two releases, delete it.
- **Edits apply to the *next* run, not this one.** Claude Code loads `SKILL.md` once at invocation
  and doesn't re-read it, so don't edit expecting current-run behaviour to change.
- **Never weaken a safety rule to make a run pass.** If a standing rule or a preflight check is
  genuinely blocking legitimate work, that is a question for the maintainer (rule 6), not a
  unilateral edit.

Commit skill changes **separately** from the DAT work, in the same PR, so the release diff stays
readable. Then list them in the Phase 10 report under a short "what I taught this skill" line — the
maintainer reviews these like any other change.

## If the run has to abort

Say so immediately with what completed and what didn't. The branch holds the partial work — leave
it, don't try to unwind it. Restore only global state you changed: the Flutter SPM setting (Phase 6)
and the CocoaPods baseline. Never `git checkout` or `git reset` across the maintainer's uncommitted
work.
