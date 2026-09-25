---
name: dat-update
description: Update this plugin to an explicitly requested Meta Wearables DAT SDK version, including implementation, verification, PR, and isolated review. Stops before merge and publish.
---

# DAT SDK update in Codex

Read and follow the shared [DAT update workflow](../../../.claude/skills/dat-update/SKILL.md).
Keep that file, its scripts, and its references as the single source of truth for the update process.
Resolve its relative links against `.claude/skills/dat-update/`, and run shell commands from the
repository root using explicit working directories; Codex shell calls do not retain `cd` or variables.

Apply these Codex adaptations:

- Invoke with `$dat-update <dat-version>`. Interpret `$ARGUMENTS` in the shared workflow as the
  version explicitly supplied by the user; ask if missing. Discussing or editing the skill does
  not authorize running the update or its preflight.
- Claude frontmatter (`model`, `effort`, `disallowed-tools`, and `disable-model-invocation`) does
  not configure Codex. Explicit-only invocation is configured in `agents/openai.yaml` here.
  The shared no-merge, no-tag, no-publish rules remain standing instructions throughout the run,
  not a tool-level enforcement mechanism.
- The maintainer selects the session model and reasoning effort in Codex. Recommend a flagship
  model at max effort for the actual update; do not claim the skill changes these settings or
  infer model changes from perceived response quality.
- Read applicable `AGENTS.md` instructions as well as the shared workflow's `CLAUDE.md` and
  maintainer documentation. Use the repository's required branch naming convention.
- For Phase 9, use Codex's available subagent tool with fresh context (`fork_turns="none"`
  when supported). Provide the PR number, repository path, and the available `plugin-pr-review`
  skill location, without implementation reasoning. Use a new agent for each review round.
  If independent review is unavailable, report that limitation rather than calling self-review isolated.
- Phase 11 process improvements belong in the shared Claude workflow and resources; Codex-only
  adaptations belong here. Re-read changed instructions before relying on them in the current run.
  The maintainer authorizes ongoing improvements when use or inspection reveals a concrete benefit:
  fix recurring friction as it is discovered, preserve scope and safety rules, validate the change,
  and report what changed. Do not wait for a separate request or duplicate the shared workflow.
- Follow the shared plan-before-mutation sequence: triage Added, Changed, Fixed, and Removed for
  each platform, inspect staged artifacts, write and present the implementation plan, then implement.
  Proceed phase by phase and ask about material uncertainty before doing work that depends on it.

Do not run the preflight just to validate this adapter: it updates external SDK clones and queries
release artifacts. Validate skill structure and links without starting an SDK migration.
