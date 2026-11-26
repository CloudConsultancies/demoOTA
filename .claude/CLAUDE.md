# CLAUDE.md

Demo of Over-The-Air (OTA) updates. Scope, architecture and roadmap are
still to be defined; see README.md as they are filled in.

## Principles

- **Cheap and ephemeral.** Cloud resources exist only for a demo and are
  destroyed afterwards. No always-on paid resources unless agreed. State a
  cost impact in any issue or PR that adds cloud resources.
- **Makefile is the single entry point.** CI calls `make` targets and does
  not duplicate logic in workflow YAML.
- **No secrets in the repo.** CI reaches cloud providers through OIDC (no
  long-lived keys); signing keys and tokens are GitHub secrets.

## Architecture constraints

(Fill in once the architecture is decided.)

## Issue workflow

Work is tracked as GitHub issues (`gh` is installed and authenticated).

- **Capturing:** when a task comes up in discussion, draft the issue in
  the chat first (title, labels, body with *Context*, *Acceptance
  criteria*, *Notes*; scenarios use the scenario template). Create it with
  `gh issue create` only after the user approves the draft.
- **Labels:** `enhancement`, `bug`, `documentation`, `scenario`, `ci`,
  `security`, `cost`, `tech-debt`. Add area labels once the architecture
  is decided.
- **"Work on #N":** read it with `gh issue view N --comments`; branch
  `issue/N-short-name` from the latest `origin/main`; commit messages
  reference `Refs #N`.
- **Ask before pushing:** when the work is committed locally, stop and ask
  the user; they may review the branch locally first.
- **After approval:** push the branch and open the PR with `gh pr create`
  (body ends with `Closes #N`). Report the CI result of the branch
  (`gh run list --branch <branch>`). Never merge; the user merges.
- Questions or decisions about an issue go into an issue comment as well
  as the chat, so the history stays with the issue.

## Environment

- Dev machine: ~8 GB RAM; docker and terraform are installed. Check
  before assuming other tools.

## Gotchas

(Fill in as we learn.)
