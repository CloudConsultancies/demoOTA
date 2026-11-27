---
name: work-on-issue
description: Implement a GitHub issue of this repo end to end - read it, check it still matches the code, set its status (In progress, In review), branch from the latest origin/main (issue/N-short-name or chore/short-name), commit with "Refs #N", stop and ask before pushing, then push, open the PR with "Closes #N" and report CI, never merge. Use when the user says "work on #12", "pick up issue 12", "implement #12", "start on the S3 issue", or asks to push or open the PR for the current issue branch.
---

# Work on an issue

Steps in order. Two stops need the user: before pushing (step 5) and any
question or decision on the way (step 3).

## 1. Read the issue

```sh
gh issue view N --comments
```

If that fails with a "Projects (classic)" GraphQL error, use
`gh issue view N --json number,title,state,labels,body,comments`.

Read every comment: decisions taken there override the original body. Note
dependencies (`Depends on #M`); if one is still open, say so and ask whether to
continue.

**Check that the issue still matches the code.** Issues are often written
before their dependencies are done. Compare each acceptance criterion with the
current state of the repo (what the dependencies actually built, names,
regions, roles, make targets). List what still holds, what is outdated or not
workable as written, and the decisions that follow, each with a
recommendation. Ask the user before implementing. Then record the decisions in
an issue comment (step 3).

## 2. Create the branch

```sh
git fetch --prune
git switch -c <branch> origin/main
```

- `issue/N-short-name` for product, design and conceptual work (decisions too).
- `chore/short-name` only for repo housekeeping that changes nothing in the
  product: setup, GitHub settings, CI, tooling, dependency updates. Use it when
  the issue says so or clearly is housekeeping.
- Lowercase, digits, hyphens; the `Branch name` workflow rejects anything else
  (`^(issue/[0-9]+-[a-z0-9]+(-[a-z0-9]+)*|chore/[a-z0-9]+(-[a-z0-9]+)*)$`).
- If the working tree is dirty or the branch already exists, stop and ask.

Then set the issue's status to **In progress**:

```sh
.claude/skills/work-on-issue/set_status.sh N "In progress"
```

This is GitHub's built-in issue status (Backlog, Todo, In progress, In review,
Done, Not planned, Duplicate). It is not a label and not a Projects field, and
`gh` has no subcommand for it; the script uses GraphQL (`setIssueStatus`) and
finds the status by name.

## 3. Implement

- Work through the acceptance criteria one by one; keep a list of what each
  criterion needs.
- Follow `.claude/CLAUDE.md` (principles, architecture constraints) and the
  other project skills where they apply: `drawio-diagram` for diagrams,
  `cost-impact` when cloud resources are added or changed.
- **Questions and decisions** go into the chat *and* an issue comment, so the
  history stays with the issue:
  `gh issue comment N --body-file <scratchpad>/comment.md`.
  Post a decision only after the user has made or approved it.
- Run every check that exists locally (`make` targets, linters, the
  `drawio-diagram` checker) before committing.

## 4. Commit

- Small, logical commits. Subject line in the imperative, under ~72 characters.
- Every commit message references the issue on its own line: `Refs #N`.
- Never commit secrets (`.env`, keys, tokens, `settings.local.json`).

## 5. Stop and ask before pushing

Summarise what was done (criteria met, anything left open, checks run) and ask
the user whether to push. They may want to review the branch locally first.
Do not push until they say so.

## 6. Push and open the PR (after approval)

```sh
git push -u origin <branch>
gh pr create --base main --head <branch> --title "<title>" --body-file <scratchpad>/pr.md
```

PR body:
- *Summary* of the change, one line per acceptance criterion, ticked if met.
- *Testing*: what was run and the result.
- *Cost impact* (from the `cost-impact` skill, or "none").
- Ends with `Closes #N` on its own line (then the attribution line, if any).

Then set the issue's status to **In review**:

```sh
.claude/skills/work-on-issue/set_status.sh N "In review"
```

Then report CI:

```sh
gh run list --branch <branch>
```

If runs are still in progress, say so and give the run URLs; if one fails, read
the log (`gh run view <id> --log-failed`) and report it.

## 7. Never merge

The user merges. After they report a merge:

```sh
git switch main && git pull --ff-only && git fetch --prune && git branch -d <branch>
```

`Closes #N` closes the issue. Check that its status is **Done**
(`gh issue view N --json state`, and the status in the issue); if not, set it
with `set_status.sh N "Done"`.
