<!--
================================================================================
INSTRUCTIONS FOR AUTHORS AND AI AGENTS (read before filling in this template)
================================================================================

SOURCES OF TRUTH (read all of them before writing anything):
  1. The full diff against the base branch (git diff <base>...HEAD), not only the last commit.
  2. The commit history of this branch.
  3. The linked issue/ticket and any referenced RFC or ADR.
  4. Repository conventions: AGENTS.md, CONTRIBUTING.md, CODEOWNERS, if present.

RULES:
  - Never invent facts. If something cannot be confirmed from the sources above,
    write "TODO(author): <what is missing>" so a human resolves it before review.
    Do not fabricate links, ticket IDs, metrics, benchmarks or test results.
  - Only claim a test or check passed if it was executed in this session or CI
    shows it. Otherwise mark it explicitly as "not run".
  - Describe behavior and intent, not line-by-line edits.
  - Single-choice fields: check exactly one box. Multi-choice fields: check all that apply.
  - Sections marked (optional) may be removed if they do not apply. Every other
    section must be filled in or answered with "N/A: <one-line reason>".
  - Keep these HTML comments in place; they are hidden in the rendered view.
  - The PR title follows the repository convention (e.g. Conventional Commits:
    type(scope): imperative summary).
  - Be concise. Reviewers read top-down: the Summary must stand on its own.
-->

## Summary

<!--
One to three sentences: what changes for users or for the system, and why.
A reviewer who reads only this section should understand the PR.
-->

**Closes:** <!-- Use a closing keyword so the issue auto-links and auto-closes, e.g. "Closes #123" or "JIRA-1234". Write "N/A" if there is none. -->

---

## Context & Motivation

<!--
- The problem or requirement this PR addresses and why it matters now.
- Link the RFC / ADR / design doc if one exists. Do not invent links.
-->

- **Problem:**
- **Why now:**
- **RFC / ADR / Design doc:** <!-- link or N/A -->

---

## Changes

<!--
Group by functional area (e.g. Core Logic, API, Data, Infrastructure, UI).
Summarize behavior per area; do not list files.
-->

-

### Out of Scope

<!--
What this PR intentionally does NOT do, and known follow-ups (link issues if created).
This prevents scope creep in review and tells reviewers what not to ask for.
-->

-

---

## Technical Decisions & Trade-offs

<!--
- Key design decisions and the reasoning behind them.
- Alternatives considered and why they were discarded.
- Performance, complexity or maintainability costs accepted.
-->

-

---

## Risk & Impact

<!--
Risk definitions:
  Low:    isolated change, trivially reversible, no contract or data changes.
  Medium: touches shared code paths, public contracts or configuration; reversible with a deploy.
  High:   data migrations, auth/security, payments, or anything hard to reverse.
-->

**Risk level** (choose one):
- [ ] Low
- [ ] Medium
- [ ] High

**Affected services / components:**

**Impact flags** (check all that apply and explain each below):
- [ ] Breaking change to an API, event or public contract
- [ ] Database / schema migration (state whether it is backward-compatible and reversible)
- [ ] New or changed configuration / environment variables (names only, never values)
- [ ] New or upgraded dependencies
- [ ] Behind a feature flag (name it and its default state)
- [ ] None of the above

**Details:**
<!-- Explain every checked flag. Delete this line if "None of the above" is checked. -->

---

## Security & Privacy

<!-- Check all that apply. If any box is checked, describe the mitigation. -->

- [ ] Touches authentication, authorization or session handling
- [ ] Handles PII or other sensitive data
- [ ] Processes untrusted input (user input, external APIs, files)
- [ ] Changes permissions, secrets management or network exposure
- [ ] None of the above

**Mitigations:**

---

## Deployment & Rollback

<!--
- Deploy prerequisites or ordering (e.g. run migration before deploying service X).
- How to roll back, and whether rollback is safe after data has been written.
- What to watch after deploy: dashboards, logs, alerts, key metrics.
-->

- **Prerequisites / ordering:**
- **Rollback plan:**
- **Post-deploy monitoring:**

---

## Verification

### Automated

<!--
List the exact commands run and their outcome. Mark anything not executed as "not run".
-->

- [ ] Unit tests added/updated: `path/to/test`
- [ ] Integration / E2E tests added/updated: `path/to/test`
- [ ] Commands executed and result:

```bash
# e.g. pnpm test --filter <pkg>   -> passed (42 tests)
```

### Manual

<!--
Step-by-step instructions a reviewer can reproduce, each with its expected result.
Include environment, test data and feature flag state when relevant.
-->

1. **Step:**  → **Expected:**
2. **Step:**  → **Expected:**

---

## Reviewer Guide

<!--
Help reviewers spend their attention where it matters.
-->

- **Start here:** <!-- entry point file or module -->
- **Needs careful review:** <!-- tricky logic, concurrency, security-sensitive code -->
- **Safe to skim:** <!-- generated code, lockfiles, mechanical renames, snapshots -->
- **Open questions for reviewers:** <!-- decisions you want input on, or N/A -->

---

## Screenshots / Visual Artifacts (optional)

<!--
Before/after UI screenshots, recordings, network payloads or benchmarks.
-->

| Before | After |
| ------ | ----- |
|        |       |

---

## Readiness Checklist

<!-- The human author checks these personally; agents must leave them unchecked. -->

- [ ] I have read and understand every line in this diff and can explain it in review.
- [ ] Tests, links and claims in this description are real and verified.
- [ ] All `TODO(author)` markers in this description have been resolved.
- [ ] Code follows repository conventions and passes local linters / type checks.
- [ ] Documentation updated where behavior changed (inline docs, API schemas, README, wiki).
- [ ] CI checks, security scans and test suites pass.
- [ ] No secrets, credentials or sensitive values are committed.
- [ ] PR is scoped to a single concern; unrelated changes were split out.
