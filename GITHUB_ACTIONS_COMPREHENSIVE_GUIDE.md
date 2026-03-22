# GitHub Actions Comprehensive Guide

## 1. What GitHub Actions Is
GitHub Actions is GitHub’s built-in CI/CD and automation platform.  
It lets you run automated tasks when events happen in your repository, such as:

- Code push
- Pull request opened
- Release published
- Manual trigger
- Scheduled time (cron)

Common uses:

- Run tests/lint
- Build Docker images
- Deploy to VPS/cloud
- Auto-label PRs/issues
- Security scanning
- Notification workflows

---

## 2. Core Terminologies

## 2.1 Workflow
A YAML file in `.github/workflows/` that defines automation logic.

Example file: `.github/workflows/ci.yml`

A workflow contains:

- Triggers (`on`)
- One or more jobs (`jobs`)
- Job steps (`steps`)

## 2.2 Event
The trigger that starts a workflow.

Examples:

- `push`
- `pull_request`
- `workflow_dispatch` (manual)
- `schedule`
- `workflow_run` (run after another workflow)

## 2.3 Job
A set of steps that run on a runner.  
Jobs run in parallel by default unless you define dependencies with `needs`.

## 2.4 Step
A single unit in a job:

- Run shell command (`run`)
- Execute an action (`uses`)

## 2.5 Action
A reusable automation component.

Types:

- JavaScript action
- Docker action
- Composite action
- Reusable workflow (`workflow_call`)

Examples:

- `actions/checkout@v4`
- `actions/setup-node@v4`
- `docker/build-push-action@v6`

## 2.6 Runner
The machine executing your job.

Types:

- GitHub-hosted runner (`ubuntu-latest`, `windows-latest`, `macos-latest`)
- Self-hosted runner (your own machine/VM)

## 2.7 Artifact
Files produced by workflow and uploaded for later use/download.

Example: test reports, build outputs.

## 2.8 Cache
Dependency/build cache to speed up workflows.

Example: npm/pnpm cache, pip cache.

## 2.9 Environment
A deployment target with protection rules and secrets.

Example: `staging`, `production`.

## 2.10 Secrets and Variables
- `secrets`: encrypted sensitive values (tokens, keys)
- `vars`: non-sensitive config values

Use in workflow with `${{ secrets.NAME }}` and `${{ vars.NAME }}`.

## 2.11 Contexts
Structured metadata available in expressions.

Common contexts:

- `github` (repo/event details)
- `env`
- `secrets`
- `vars`
- `job`
- `steps`
- `runner`
- `matrix`

## 2.12 Matrix Strategy
Run one job across multiple combinations.

Example: multiple Node versions and OSes.

## 2.13 needs
Defines job dependency graph (DAG).

If `deploy` needs `build`, deploy starts only after build succeeds.

## 2.14 Condition (`if`)
Controls whether a job/step runs.

Example: only deploy on `main`.

## 2.15 Concurrency
Prevents overlapping runs (e.g., only one production deploy at a time).

---

## 3. How GitHub Actions Works (Execution Flow)

1. GitHub receives an event (e.g., push).
2. It scans workflow YAML files in `.github/workflows/`.
3. Matching workflows are queued.
4. Jobs are assigned to runners.
5. Each job executes steps in order.
6. Job outputs/logs/artifacts are stored.
7. Workflow status is reported (success/failure/cancelled).

Important behavior:

- Jobs are isolated; files aren’t shared between jobs unless artifacts/cache are used.
- Each job starts from a clean environment (on hosted runners).
- Secrets are masked in logs.

---

## 4. Workflow File Structure

Basic pattern:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

env:
  NODE_ENV: test

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
      - run: npm ci
      - run: npm test
```

Key top-level fields:

- `name`
- `on`
- `env`
- `permissions`
- `concurrency`
- `jobs`

---

## 5. Trigger Types You’ll Use Most

- `push`: run when commits are pushed
- `pull_request`: run PR validation
- `workflow_dispatch`: manual run from UI
- `schedule`: cron-based runs
- `workflow_run`: chain workflows (e.g., deploy after build)
- `release`: trigger on release lifecycle
- `repository_dispatch`: external API-triggered

---

## 6. Expressions and Syntax

GitHub Actions expression syntax:

```yaml
if: github.ref == 'refs/heads/main'
```

Examples:

- `${{ github.sha }}`
- `${{ github.actor }}`
- `${{ secrets.DOCKERHUB_TOKEN }}`
- `${{ vars.DOCKERHUB_USERNAME }}`
- `${{ startsWith(github.ref, 'refs/tags/v') }}`

---

## 7. Job Dependencies and Parallelism

Default:

- Jobs run in parallel

Dependency:

```yaml
jobs:
  test:
    ...
  build:
    needs: test
  deploy:
    needs: build
```

This creates a reliable CI/CD pipeline chain.

---

## 8. Permissions Model (Very Important)

Use least privilege with `permissions`:

```yaml
permissions:
  contents: read
  packages: write
```

`GITHUB_TOKEN` permissions should be scoped tightly for security.

---

## 9. Secrets, Variables, and Environments

Where to set:

- Repo Settings -> Secrets and variables -> Actions
- Environment-specific secrets under Environments

Best practice:

- Use secrets for credentials
- Use variables for usernames/config constants
- Never hardcode credentials in YAML

---

## 10. Reusable Building Blocks

## 10.1 Reusable Workflow (`workflow_call`)
Create shared workflow used by many repos/services.

## 10.2 Composite Action
Bundle repeated steps into a local/custom action.

Use when logic repeats across workflows.

---

## 11. Caching and Artifacts

Caching:

- Speeds dependency restore.
- Keyed by lockfiles/hash.

Artifacts:

- Persist build outputs/reports between jobs or for downloads.

---

## 12. CI/CD Pattern (Recommended)

Typical production chain:

1. `test` workflow: lint, type-check, unit tests
2. `build` workflow: build package/docker image
3. `publish` workflow: push image/package
4. `deploy` workflow: deploy to staging/prod
5. `post-deploy checks`: health checks/smoke tests

Use branch rules:

- PR required checks
- No direct push to `main` (optional team policy)

---

## 13. Common Deployment Pattern (Docker + VPS)

- Build image in GitHub Actions
- Push to Docker Hub (tag as `sha-<commit>` + `latest`)
- SSH to VPS
- `docker compose pull`
- `docker compose up -d --force-recreate`
- Verify health endpoint

This gives immutable, traceable deploys.

---

## 14. Debugging Failed Workflows

Check in this order:

1. Trigger conditions (`on` branches/tags)
2. Job `if` conditions
3. Secrets/variables availability
4. Permissions issues
5. Dependency install/build errors
6. Network/registry/auth failures
7. Runner environment assumptions

Useful tips:

- Add explicit validation step for required secrets/vars.
- Print safe debug data (never secrets).
- Re-run failed jobs with same inputs.

---

## 15. Security Best Practices

- Pin third-party actions to trusted versions (prefer SHAs for strict security)
- Minimize token permissions
- Use environments + required reviewers for production deploy
- Protect `main` branch with required checks
- Rotate secrets regularly
- Avoid `pull_request_target` misuse in untrusted contributions
- Keep dependency lockfiles and scanners in CI

---

## 16. Performance Best Practices

- Use caching correctly (lockfile-based keys)
- Run independent jobs in parallel
- Split fast checks and slow checks
- Use path filters to skip irrelevant workflows
- Use reusable workflows to standardize and reduce maintenance
- Cancel stale runs with concurrency groups

---

## 17. Example End-to-End Pipeline (Conceptual)

- Event: push to `main`
- Workflow A (`test`) validates quality
- Workflow B (`build`) runs if tests pass, pushes Docker image with `sha` tag
- Workflow C (`deploy`) picks that tag and deploys to VPS
- Health check validates rollout
- If unhealthy, fail deployment and alert team

---

## 18. Quick Terminology Cheat Sheet

- Workflow: whole YAML automation definition
- Event: trigger
- Job: runner-executed stage
- Step: command/action in a job
- Action: reusable step logic
- Runner: execution machine
- Artifact: uploaded output files
- Cache: speed-up storage
- Matrix: multi-variant job execution
- `needs`: job dependency
- `if`: conditional execution
- Secrets: sensitive values
- Variables: non-sensitive values
