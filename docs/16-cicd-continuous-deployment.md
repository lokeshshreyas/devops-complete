# 16. CI/CD: Continuous Deployment (Optional, Opt-In)

**This is optional, and off by default.** Nothing in this section changes how the core
workshop ([RUNBOOK.md](../RUNBOOK.md)) or the CI validation pipeline
([docs/10-cicd-pipeline.md](10-cicd-pipeline.md)) work. You explicitly turn CD on by running
one script.

## What "CD" means here

`docs/10-cicd-pipeline.md` covers `.github/workflows/ci.yml` — **CI**, which validates your
code on every push but never touches AWS. This document covers `.github/workflows/cd.yml` —
**CD**, which *does* touch AWS: after you push a change to `terraform-docker/`,
`terraform-eks/`, `kubernetes/`, or `src/`, it automatically applies that change to whichever
infrastructure you already have deployed.

## Why this is opt-in, and why it's tricky on KodeKloud

The KodeKloud AWS Playground gives you **temporary, session-scoped credentials** — an access
key, a secret key, and a session token that all stop working when your ~3 hour session ends.
A real company's CD pipeline uses long-lived credentials (usually a GitHub OIDC role, never
static keys) tied to a permanent AWS account. Neither of those things is true here, so:

- `scripts/advanced/06-setup-cicd.sh` uploads **your current session's** temporary credentials
  as GitHub Actions secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`,
  `AWS_REGION`).
- CD works for the rest of that session.
- The moment the session's credentials expire, `scripts/advanced/07-cd-apply.sh` — the script
  the workflow runs — fails fast with an explicit message telling you to start a new KodeKloud
  session, re-run `06-setup-cicd.sh`, and push again. It will not hang or fail silently.
- This is a deliberate trade-off for a learning environment, not a production pattern. See
  "Graduating to a real setup" below for how this would differ on a permanent AWS account.

## How it knows which stack to update

Both deployment paths in this project write a one-line marker file,
`.thermos/active-stack`, containing `docker`, `eks`, or `none`:

| Script | Writes |
|---|---|
| `scripts/03-deploy.sh` | `docker` (after a successful `terraform apply`) |
| `scripts/advanced/03-k8s-deploy.sh` | `eks` (after manifests are applied) |
| `scripts/07-destroy.sh` | `none` (if it was `docker`) |
| `scripts/advanced/04-k8s-destroy.sh` | `none` (if it was `eks`) |

`scripts/advanced/07-cd-apply.sh` reads that file and applies changes to the matching stack
only — it never tries to stand up infrastructure you haven't already created by hand.

## Setting it up

1. Deploy something first — either `./scripts/03-deploy.sh` (Docker/EC2) or
   `./scripts/advanced/02-eks-up.sh` + `./scripts/advanced/03-k8s-deploy.sh` (Kubernetes/EKS).
   CD updates existing infrastructure; it doesn't create it from nothing.
2. Create an empty GitHub repository (no README, no `.gitignore` — this project already has
   both): <https://github.com/new>
3. Create a GitHub Personal Access Token. `scripts/advanced/06-setup-cicd.sh`'s header comment
   explains exactly which type and permissions — in short: a fine-grained PAT scoped to this
   one repo with **Contents: Read and write**, **Actions: Read and write**, and
   **Secrets: Read and write** (or a classic PAT with the `repo` + `workflow` scopes).
4. Run it:
   ```bash
   chmod +x scripts/advanced/06-setup-cicd.sh
   ./scripts/advanced/06-setup-cicd.sh
   ```
   It will ask for the repo URL and the token, push this project to `main`, and register the
   AWS secrets. The token itself is never written to disk or committed.
5. Make a change (e.g. edit `terraform-docker/variables.tf`'s default instance type, or a
   Kubernetes resource limit in `kubernetes/02-backend.yaml`), commit, and push:
   ```bash
   git add -A && git commit -m "test CD" && git push
   ```
6. Watch it run under the **Actions** tab of your repo, or with `gh run watch` if you have the
   GitHub CLI installed.

## Trying it without waiting for a real push

`scripts/advanced/07-cd-apply.sh` is a plain, non-interactive script — run it locally any time
to see exactly what CD would do:

```bash
./scripts/advanced/07-cd-apply.sh
```

## Turning it off

Delete or rename `.github/workflows/cd.yml`, or simply stop pushing to `main` — GitHub only
runs workflows that exist in the repository. Removing the `AWS_*` secrets (repo Settings →
Secrets and variables → Actions) disables it just as effectively without touching any files.

## What this teaches

- The difference between CI (validate) and CD (deploy), and why a project doesn't get CD "for
  free" just because it has CI
- Why credential lifetime is the deciding factor in whether automated deployment is safe, not
  just whether it's technically possible
- GitHub Actions secrets: how they're encrypted client-side with the repo's public key before
  upload (libsodium sealed box), and why the token that sets them is never persisted
- Driving Terraform and `kubectl` from a CI runner instead of a laptop — the same commands,
  a different execution environment
- Using a simple marker file as a lightweight way to make automation environment-aware,
  instead of hard-coding an assumption about which stack is active

## Graduating to a real setup

On a **permanent** AWS account (not a KodeKloud sandbox), you would replace steps 3–4 above
with:
- A dedicated IAM role with a trust policy scoped to your GitHub repo, assumed via
  [GitHub's OIDC provider](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
  — no static keys stored in GitHub at all, nothing to rotate, nothing to leak.
- `aws-actions/configure-aws-credentials@v4`'s `role-to-assume` input instead of
  `aws-access-key-id` / `aws-secret-access-key`.
- Branch protection + required reviews on `main`, and a `terraform plan` job on pull requests
  (showing the diff before merge) feeding into the `terraform apply` job on merge.

This is exactly the direction the companion `ecommerce-devops-project` takes further, with
ArgoCD-based GitOps instead of a single apply job.
