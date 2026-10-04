---
name: land
description: >-
  Land explicitly requested Monty changes into the primary repository's local
  main branch. Invoke only when the user requests landing or merging the relevant
  changes, not for review, preparation, passing checks, or skill installation.
disable-model-invocation: true
metadata:
  delta-action: land
---

# Land Monty changes

## Scope and authorization

This workflow applies to the Phoenix project whose `mix.exs` defines
`Monty.MixProject` and `app: :monty`. Its destination is the primary repository's
local `main` branch. It does not publish branches, open pull requests, push to a
hosting service, deploy, or migrate a development or production database.

An explicit request to run this skill supplies landing intent. Proceed through
the checks and landing operation; do not ask again whether to merge.
Installation, review approval, and passing checks alone are not landing requests.

Operate and verify in the attached Monty checkout. An explicit invocation
of /land also authorizes direct writes to the verified primary local Monty
checkout resolved from the local remote, solely to perform this workflow
and fast-forward its main branch. No separate attachment or access
confirmation is required.

All destination identity checks, pending-work safeguards, verification,
and recovery requirements still apply. This does not authorize pushing,
publishing, deployment, database migration, or unrelated filesystem edits.

## Repository evidence

Recheck these sources at execution time; honor any applicable new requirements:

- `AGENTS.md`, **Project guidelines**, requires `mix precommit` after changes.
  Its remaining instructions govern applicable code, authentication, migration,
  template, and test changes.
- `mix.exs`, `project/0`, declares Elixir `~> 1.17` and the Phoenix LiveView
  compiler. `cli/0` selects the test environment for `precommit`.
- `mix.exs`, `aliases/0`, defines
  `precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]`
  and `"assets.build": ["compile", "tailwind monty", "esbuild monty"]`.
  These definitions support the verification commands below.
- `config/config.exs`, the `:tailwind` and `:esbuild` `monty` configurations,
  defines the CSS input, bundled JavaScript entry point, output paths, and
  build-path-dependent module resolution used by the asset build.
- `README.md`, **Verification**, specifies
  `node --test assets/js/*.test.mjs`. The matching
  `assets/js/canvas_geometry.test.mjs` and `assets/js/canvas_drag.test.mjs`
  import `node:test` and `node:assert/strict`; no npm test wrapper is needed.
- `mix.exs`, `aliases/0`, makes `test` create and migrate the test database.
  `config/test.exs` selects `monty_test.db`, SQL Sandbox, and the test mailer.
  Do not substitute `mix setup` or `mix ecto.reset` for verification.
- `.gitignore` excludes build artifacts, dependencies, generated asset bundles,
  and SQLite files. Do not force-add these, local backups, or credentials.
- `README.md`, **Deployment and remaining scope**, requires preserving
  applicable upstream license notices when importing source or assets.

At configuration time, only the local repository backlink was configured:
`local` pointed at `/Users/nickgartmann/Development/Sufficient/monty/.git`.
Both source and primary repository used `main`. No hosting remote, CI workflow,
contribution template, authoritative landing script, active Git hook, or signing
requirement was found. These observations are not permanent exemptions:
inspect current repository policies, hooks, signing settings, remotes, and any
CI/review requirements before landing. Do not infer that a newly added hosting
remote authorizes publication.

## 1. Identify source, destination, and requested scope

1. Inspect the source checkout without optional Git locks:
   - `git rev-parse --show-toplevel`
   - `git branch --show-current`
   - `git rev-parse HEAD`
   - `git --no-optional-locks status --short --untracked-files=all`
   - `git diff` and `git diff --cached`
   - `git remote -v`
2. Identify all requested committed and uncommitted changes. Do not assume the
   work is already committed. Include relevant new files and documentation;
   exclude unrelated edits, generated outputs, local data, and secrets.
   Ask a focused scope question only when ownership or intent is unclear.
3. Resolve the primary destination from the current `local` remote when present.
   Treat it as a local repository backlink, not a publishing remote. Verify it
   is the intended Monty repository and determine its actual working directory,
   checked-out branch, `main` commit, worktrees, and working-tree state.
   If `local` is missing or identifies a different repository, stop and ask
   for the intended local destination rather than guessing.
4. Confirm destination access under **Scope and authorization** before any
   destination write. Never operate on an unexpected checkout or switch the
   user's active branch to make the procedure convenient.
5. Check for in-progress merge/rebase/cherry-pick operations, applicable
   instruction files, contribution policies, configured signing, and active
   hooks in source and destination. Stop for an unrelated in-progress operation.
   Carry conditional contribution requirements through accurately: obtain any
   required human-authored submission text, signatures, reviews, agreements,
   changelog entries, or documentation only when applicable and unmet.
   Preserve applicable license notices for any imported source or assets.

Use `GIT_EDITOR=true` for commits and merges. Do not invoke interactive editors,
interactive rebases, force pushes, resets that discard work, or history rewrites.
Respect configured signing; do not bypass a required signature or hook.

## 2. Prepare a candidate without overwriting other work

1. Work on a uniquely named local candidate branch in the attached source
   checkout. Record the original branch and commit. Do not reset or rewrite the
   original branch or clean away its pending changes.
2. Stage only the files and hunks established as part of this request, including
   relevant untracked files. Do not use blanket staging when unrelated edits
   are present.
3. Make a descriptive imperative-subject commit for the requested work using
   `GIT_EDITOR=true git commit -m "<descriptive subject>"`, replacing the example
   with the actual subject. There is no project commit-prefix requirement.
   Preserve unrelated unstaged and staged edits; if they cannot be safely
   isolated, stop rather than stash or commit them indiscriminately.
4. Fetch the latest destination `main` into the source repository using its
   verified local repository path. Merge that exact commit into the candidate,
   fast-forwarding when possible and otherwise using a normal merge commit.
   Do not squash or rewrite existing commits.
5. Resolve conflicts automatically only when the intended combined result is
   clear. Preserve both the requested feature and newer destination behavior;
   do not choose blanket "ours" or "theirs". On ambiguous conflicts, stop and
   explain the files and decision needed. Do not report the change as landed.
6. Finish any clear conflict resolution with a noninteractive merge commit.
   Record the candidate commit and tree that will be verified.

## 3. Verify the exact combined candidate

Check that Git, an Elixir runtime satisfying `mix.exs`, compatible Erlang/OTP,
and a Node runtime supporting `node:test` and `--test` are available.
Do not invent a pinned Node version: none is declared in this project.
Missing global tools or dependencies that cannot be retrieved are blockers;
do not install system-wide tools without authorization.

Run in the attached source checkout on the combined candidate:

```sh
MIX_ENV=test mix precommit
node --test assets/js/*.test.mjs
MIX_ENV=test mix assets.build
git diff --check
git diff --cached --check
```

Sources for the exact command group: `mix.exs` `cli/0` and `aliases/0`;
`README.md` **Verification**; the two `assets/js/*.test.mjs` suites;
`config/config.exs` asset task definitions; and `config/test.exs`.
Explicit test-environment compilation avoids sharing the development server's
loaded modules and `_build/dev` artifacts.

If dependency retrieval is necessary, inspect the changed `mix.exs` and
`mix.lock` first and use the standard `mix deps.get` task documented by
`mix help deps.get`. Fetch only declared dependencies; do not upgrade
dependencies or install unrelated packages. Run the full command group again
after dependencies are available.

`precommit` can format files or update the lockfile. Review those changes,
commit only applicable corrections, and rerun verification against the final
candidate. Passing checks on an earlier tree are not sufficient.
Fix relevant failures without weakening tests, policy, warnings-as-errors,
authorization, or safety boundaries.

For UI interactions or other behavior not adequately established by these
checks, perform the relevant local workflow verification as well. Use isolated
test build artifacts for any verification server and clean up only the
processes and test data created for it. Do not stop the user's running server.

If current repository policy requires remote CI or reviews, verify all
applicable required checks have passed for the exact candidate and required
approvals are present. Pending, failing, missing, or unverifiable checks block
landing. This local-only workflow does not itself authorize external
publication; stop for the required authorization or workflow update if remote
steps become necessary.

## 4. Require a Claude review

After verification passes and all applicable corrections are committed, run
`claude -p` in the attached source checkout to review the exact combined
candidate against the destination `main` commit integrated into it. Review the
full landing diff, not just the last commit or uncommitted changes.

Substitute the recorded commit hashes in this command before running it:

```sh
claude -p "Perform a read-only code review of the Monty landing candidate. The destination main baseline is <destination-main-commit> and the verified candidate is <verified-candidate-commit>. Inspect git diff <destination-main-commit> <verified-candidate-commit> and relevant surrounding code, tests, and applicable AGENTS.md/AGENT.md instructions. Review committed content at those exact hashes, not unrelated working-tree edits. Do not modify files, create commits, or run landing commands. Look for substantive correctness bugs, regressions, security issues, data-loss risks, violations of project requirements, and missing tests that leave important behavior unverified. Skip cosmetic preferences and optional refactors. For each finding, give severity, file and line, a concrete failure scenario, and supporting evidence. State explicitly whether there are substantive findings. If you cannot complete the review or verify a material concern, state that limitation rather than approving."
```

- Inspect Claude's complete output and exit status. A successful process exit
  alone is not review approval. Record the reviewed baseline and candidate
  hashes and summarize the review result in the thread.
- **Pause landing on any substantive finding.** Report the findings and wait
  for the user's direction before fixing or proceeding. Do not silently
  dismiss findings, treat them as follow-ups, or advance destination `main`.
  Cosmetic suggestions alone need not block landing.
- If Claude is unavailable, fails, cannot complete the review, or leaves a
  material concern unresolved, pause and explain the blocker. Do not install
  global tools, bypass permissions, or replace the required review with your
  own approval.
- After any candidate change, including a review fix or newer destination
  integration, repeat the full verification group and this Claude review for
  the new exact candidate. An earlier review does not approve a changed tree.
- Proceed only when verification passes and the completed Claude review has
  no unresolved substantive findings. A disputed finding remains a blocker
  until the user explicitly resolves it or authorizes an exception; record
  any exception in the landing summary.

## 5. Safeguard destination work

Before landing, inspect and record the destination's branch, `main` commit,
staged changes, unstaged changes, and untracked files again.

- If destination `main` advanced, fetch and integrate its new commit into the
  candidate, resolve only clear conflicts, and repeat the full verification
  group and Claude review on the resulting candidate. Never land an outdated
  integration or rely on an earlier candidate's review.
- If the destination is on another branch, has unrelated pending work, or its
  identity changed, stop without switching branches or overwriting anything.
- A dirty destination is not automatically disposable. The primary repository
  can already contain the same uncommitted edits as the requested source work.
  Accept that case only after verifying every dirty path, complete file content,
  deletion, and file mode is represented exactly in the verified candidate.
  Matching filenames or similar-looking hunks are not sufficient.

For exactly matching destination pending edits, after destination access is
authorized, preserve their staged/unstaged state and any matching untracked
files in a named local stash checkpoint using
`git stash push --include-untracked -m "land: preserve matching incoming edits" --`
followed by the explicit matching path list. Record its object ID and confirm it exists.
Do not include ignored files or unrelated paths. Recheck the destination commit
and clean state immediately afterward. Keep this checkpoint after success;
do not automatically drop it, since deletion would remove a recovery reference.

If landing stops after checkpointing but before advancing the destination,
restore the checkpoint with `git stash apply --index <recorded-stash-object>`
only when the destination is still on its recorded original commit and its
working tree is clean. Otherwise leave it intact and explain exactly where
the pending work is preserved rather than applying it over newer edits.

## 6. Perform and confirm landing

1. Only after all required verification and the Claude review pass, ensure the
   authorized primary destination is still on `main`, at the commit integrated
   into the candidate, and clean. If it changed, stop or return to integration,
   verification, and Claude review without overwriting the change.
2. Make the exact verified candidate commit available to the destination by
   fetching it from the attached source repository's Git directory. This is
   local transfer only, not a push to a hosting service.
3. Confirm the recorded destination commit is an ancestor of the candidate
   using `git merge-base --is-ancestor`, then run in the authorized destination:

   ```sh
   GIT_EDITOR=true git merge --ff-only <verified-candidate-commit>
   ```

   Substitute the exact verified hash. A non-fast-forward is a blocker:
   do not force it or rewrite destination history.
4. Verify at the actual primary destination, not merely the source clone:
   - checked-out branch is `main`;
   - `git rev-parse HEAD` equals the verified candidate hash;
   - working tree and index are clean;
   - no merge operation remains unfinished;
   - the requested changes and any installed skill are present in the landed tree.
5. Confirm success with the landed commit and verification results. Mention
   retained recovery checkpoints and any meaningful follow-up. If any genuine
   blocker prevents the destination update, state that the changes have not
   landed and explain the blocker; preparing a commit or completing checks
   is not a successful landing.

Leave unrelated work, other local branches, and recovery checkpoints untouched.
Do not delete the candidate branch automatically or change the source's branch
when doing so would endanger unrelated pending work.
