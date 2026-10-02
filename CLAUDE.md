# terraform/ - CLAUDE.md

## Overview

This directory governs all Terraform and OpenTofu work in the `terraform-hetzner-kafka` project. Claude must follow these standards for every piece of infrastructure code written or reviewed here. Linting is enforced via pre-commit (terraform fmt, tflint, trivy).

## Global standards — see ~/.claude/DIGITALIS.md

Shared engineering standards live in `~/.claude/DIGITALIS.md` (installed from the `claude-skills` marketplace) and are **not** repeated here: terse communication, KnowledgeRelay/RAG sourcing for AxonOps/Digitalis/customer questions, secrets management, signed + DCO commits with brand-based identity, branding, README requirements, and the NEVER-DO list. This file covers only Terraform-specific workflow and tooling.

## Required Claude Code plugins

Agents and slash commands live in the AxonOps shared marketplace at
`bitbucket.org/digitalisio/claude-skills`. Install once per developer using Claude Code's native plugin marketplace:

```text
/plugin marketplace add git@bitbucket.org:digitalisio/claude-skills.git
/plugin install engineering-agents@axonops-claude-skills
/plugin install terraform-bootstrap@axonops-claude-skills
/plugin install kubernetes@axonops-claude-skills          # OPTIONAL: install if this module manages Helm/Kustomize/k8s manifests
/plugin install kafka@axonops-claude-skills               # OPTIONAL: install if this module provisions MSK, Confluent, Strimzi, or any Kafka
/plugin install cassandra@axonops-claude-skills           # OPTIONAL: install if this module provisions Cassandra/DSE/Astra/k8ssandra
```

### Keeping skills current

Plugins evolve. Pull the latest catalog and update everything in one go:

```text
/plugin marketplace update axonops-claude-skills
/plugin update
```

Optional opt-in: a SessionStart hook can warn when this marketplace is behind. Paste into your personal `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "startup",
      "hooks": [{
        "type": "command",
        "command": "test -d ~/.claude/plugins/marketplaces/axonops-claude-skills && git -C ~/.claude/plugins/marketplaces/axonops-claude-skills fetch --quiet 2>/dev/null && [ \"$(git -C ~/.claude/plugins/marketplaces/axonops-claude-skills rev-list HEAD..origin/main --count 2>/dev/null || echo 0)\" -gt 0 ] && echo 'axonops-claude-skills: updates available — run /plugin marketplace update axonops-claude-skills && /plugin update'"
      }]
    }]
  }
}
```

The legacy `git clone … install.sh --plugin <name>` flow is still supported for non-Claude-Code consumers but is deprecated — it cannot track versions or report updates.

Plugins used:
- `engineering-agents` — `secrets-auditor`, `docs-quality-reviewer`, `devops`, `security-reviewer`, `tech-decision-maker`, `issue-writer` (generic)
- `terraform-bootstrap` — `terraform-specialist`, `issue-writer` (Terraform-specific), `terraform-bdd-tests` skill, `/create-pr`, `/create-jira-ticket`, `/create-github-issue`
- BDD skills: `engineering-agents:bdd-guidelines` (generic rules — load alongside the stack BDD skill) and `terraform-bootstrap:terraform-bdd-tests` (terraform-compliance / terratest+godog realisation)

When this CLAUDE.md references a bare agent name (e.g. `terraform-specialist`), it resolves to the marketplace plugin's namespaced version (`terraform-bootstrap:terraform-specialist`).

## Workflow — Agent Gates

These agents are mandatory gates, not optional tools. Do not skip them.

### Creating issues and tickets

Use the slash commands to create issues — they enforce the full quality gate workflow automatically:

- **`/create-jira-ticket`** — for Bitbucket-hosted repos (default). Runs the issue-writer agent, checks for duplicates via `atlassian:triage-issue`, then files via Atlassian MCP.
- **`/create-github-issue`** — for GitHub-hosted repos only. Runs the issue-writer agent, checks for duplicates, then files via `gh issue create`.

Every issue must have: summary, detailed requirements, numbered acceptance criteria, specific testing requirements (named commands, not "add tests"), documentation requirements, dependencies, and labels. If any section is missing or vague, rewrite it before filing.

### Before writing any Terraform/OpenTofu code:

State your assumptions about variable types, backend configuration, provider versions, and module boundaries. Wait for confirmation before proceeding.

### When starting any new module or significant feature

1. **`engineering-agents:bdd-guidelines`** + **`terraform-bootstrap:terraform-bdd-tests`** — write Gherkin `.feature` files under `tests/compliance/features/` (preferred: terraform-compliance against `tofu plan`) and/or `tests/integration/features/` (terratest+godog against an applied plan). Cover the happy path AND at least one invalid/edge input. Cleanup via `defer terraform.Destroy` registered immediately after `InitAndApply`.
2. **`agent-skills:test-driven-development`** — author the failing compliance scenario(s) before adding the resources that make them pass.

### Before committing any Terraform content:

1. **secrets-auditor** — scan all changed files for plaintext secrets, hardcoded credentials, or sensitive defaults. Verdict must be SAFE TO COMMIT. If BLOCKED, fix before proceeding.
2. **terraform-specialist** — correctness, idempotency, variable validation, naming conventions, security posture, and tflint compliance. Do not commit if any ❌ issues remain.

### After completing any feature:

1. **terraform-specialist** — on all changed `.tf` files
2. **security-reviewer** — on any resources touching IAM, networking, storage, or secrets
3. **docs-quality-reviewer** — on any README or module documentation changes

### Commit messages and branch names:

- **Branch name** must include the Jira ticket key: `feat/BOOT-42-add-vpc-module`
- **PR/merge commit title** must include the Jira ticket key: `feat(BOOT-42): add VPC baseline module with flow logs`
- Individual WIP commits do not need the ticket key — the branch and PR title are the canonical reference
- Commit messages must be self-describing without the ticket (readable in `git log` without Jira access)

### Creating pull requests

Use **`/create-pr`** to create pull requests. It runs all mandatory gates automatically:

1. Verifies branch name contains Jira ticket key
2. Runs `pre-commit run --all-files`
3. Runs **secrets-auditor**, **terraform-specialist**, and **docs-quality-reviewer**
4. Verifies CHANGELOG.md and CI coverage (`tofu validate`, `tflint`, `trivy`)
5. Creates PR with Jira ticket key in title and full checklist in body

A PR must not be opened until:
- All ❌ issues are resolved
- Module README is current (inputs, outputs, examples)
- `CHANGELOG.md` is updated
- `terraform validate` and `terraform plan` (or `tofu plan`) pass cleanly

## Active Tasks

1. [NOT STARTED] Define first module
   - Status: Not Started

## Architecture & Key Decisions

- **Runtime**: OpenTofu preferred; Terraform >= 1.5 also supported
- **Linting**: tflint + trivy (security) + terraform fmt via pre-commit
- **State**: Remote backend (S3 + DynamoDB lock, or equivalent) — never local state in shared modules
- **Module pattern**: Each module is self-contained with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md` generated by terraform-docs
- **Provider pinning**: All providers must pin a `~>` minor version constraint in `versions.tf`
- **Naming**: Resources follow `<project>-<env>-<resource>` convention

## Useful Commands

```bash
# Makefile targets (run `make help` for full list)
ENVIRONMENT=dev REGION=eu-west-2 make plan     # Init + plan
ENVIRONMENT=dev REGION=eu-west-2 make apply    # Init + apply
make fmt                                        # Format all .tf files
make docs                                       # Generate README via terraform-docs

# Linting
pre-commit install                # Install hooks
pre-commit run --all-files        # Run all linting
pre-commit run --files <file>     # Run on specific files

# Direct tool access
tofu fmt -recursive               # or: terraform fmt -recursive
tofu validate                     # or: terraform validate
trivy config .                    # Security scan
tflint --recursive                # Lint
```

## Dependencies

- OpenTofu >= 1.7 or Terraform >= 1.5
- tflint >= 0.50
- trivy >= 0.50
- terraform-docs >= 0.18
- pre-commit

```bash
# macOS
brew install opentofu tflint trivy terraform-docs pre-commit
```

## Terragrunt — When to Use It

This bootstrap uses **vanilla OpenTofu**. Do not add Terragrunt to standalone module repos created from this template.

Terragrunt is the right tool for a **live infrastructure repo** — a separate repository that wires together multiple standalone modules across accounts, regions, and environments. Use it there when you need:

- `run-all` to plan/apply a dependency graph of modules in the correct order
- DRY remote state configuration shared across dozens of module calls
- Multi-account/multi-region matrix without copy-pasting backend blocks

A live infrastructure repo typically looks like:

```text
live/
  _global/
    terragrunt.hcl          # root: provider, backend bucket convention
  production/
    eu-west-2/
      postgres/
        terragrunt.hcl      # calls the standalone tf-ap-aws-postgres module
      vpc/
        terragrunt.hcl
  staging/
    eu-west-2/
      postgres/
        terragrunt.hcl
```

**Caution with `generate` blocks**: dynamically generating `.tf` files (e.g. `generate "backend"`) works but breaks `tflint`, `terraform-docs`, and LSP in the files written to `.terragrunt-cache`. Prefer `-backend-config` partial backends and `TF_VAR_` env vars where the static analysis toolchain must stay intact.

## Known Limitations & Tech Debt

None currently.

## Next Steps & Roadmap

1. Define backend configuration module
2. Add first infrastructure module
3. Configure CI pipeline for plan/apply
