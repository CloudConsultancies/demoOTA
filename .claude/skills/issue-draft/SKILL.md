---
name: issue-draft
description: Draft a GitHub issue for this repo in the chat (title, labels, body with Context, Acceptance criteria and Notes, or the scenario template for demo scenarios) and create it with gh only after the user approves. Use when the user says "draft an issue", "open an issue", "create a ticket", "capture this as a task", "add this to the backlog", or when a new task, bug or demo scenario comes up in discussion.
---

# Draft an issue

Issues are drafted in the chat first and created only after the user approves.

## 1. Gather context

- Check for duplicates: `gh issue list --state all --search "<keywords>"`. If one
  exists, propose a comment on it instead of a new issue.
- Read the parts of README.md and `.claude/CLAUDE.md` the issue touches
  (architecture constraints, roadmap phase, principles), so the draft does not
  contradict a decision already made.
- Note dependencies on other open issues (`gh issue list`).

## 2. Pick the template

| Kind of work | Template | Body sections |
|---|---|---|
| feature, infrastructure, hardening, cleanup, decision | `.github/ISSUE_TEMPLATE/task.yml` | *Context*, *Acceptance criteria*, *Notes* |
| something is broken | `.github/ISSUE_TEMPLATE/bug.yml` | *What happened*, *Expected behaviour*, *Failing workflow run*, *Logs* |
| a scripted demo | `.github/ISSUE_TEMPLATE/scenario.yml` | *Goal*, *OTA features shown*, *Steps*, *Expected observations*, *Reset*, *Notes* |

Read the template file before drafting; use its field labels as `###` headings in
the body, in the same order, so the issue looks the same as one created from the
web form.

## 3. Pick the labels

- Get the labels that exist: `gh label list --limit 100`. Use only those.
- **Type** (one or more): `enhancement`, `bug`, `documentation`, `scenario`, `ci`
  (GitHub Actions), `security`, `cost`, `tech-debt`, `compliance` (SBOM, CVE
  reports, audit log, incident records).
- **Area** (one or more, when the work touches the product):
  - `infra`: Terraform / AWS
  - `image`: Yocto layers, recipes, green/blue/red variants
  - `device`: RAUC, partitions, boot counting, watchdog, health check, update agent
  - `fleet`: fleet backend, provisioning, rollout and rollback
  - `app`: demo web app

  Pure repo tooling may have no area label.
- The template's default label (`enhancement`, `bug`, `scenario`) is always one
  of them. Add `cost` when cloud resources are added or changed, `security` for
  keys, credentials and access.

## 4. Write the draft

- **Title:** imperative or a noun phrase, specific, under ~80 characters.
- **Context:** why it is needed and what exists today.
- **Acceptance criteria:** a checklist (`- [ ]`) of checkable outcomes, not
  activities. Each item can be verified by reading the code, running a `make`
  target or looking at CI.
- **Notes:** approach ideas, dependencies (`Depends on #N`), risks, out of scope,
  the branch type when it is not obvious (`chore/...` for housekeeping), and a
  **Cost impact** line. If the issue adds or changes cloud resources, write the
  full section with the `cost-impact` skill; otherwise "Cost impact: none".
- Follow the repo principles: Makefile as the single entry point, cheap and
  ephemeral cloud, no secrets in the repo, traceable releases.

Show the draft in the chat exactly as it will be created:

```
**Title:** ...
**Labels:** `enhancement`, `infra`

### Context
...
```

## 5. Create it only after approval

Wait for an explicit approval ("ok", "create it", "looks good"). If the user asks
for changes, show the revised draft again.

Then write the body to a file in the scratchpad and create the issue:

```sh
gh issue create --title "<title>" --label "<l1>,<l2>" --body-file <scratchpad>/issue.md
```

Report the issue number and URL. Do not start work on it unless asked (that is
the `work-on-issue` skill).
