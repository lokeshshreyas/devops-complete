# 10. CI/CD Pipeline (Optional)

**This is optional and only runs if you push this project to your own GitHub repository.**
It has nothing to do with the core KodeKloud workshop, which you run entirely from your own
terminal with `./scripts/03-deploy.sh`.

## What it is — and isn't

`.github/workflows/ci.yml` is **CI (Continuous Integration)**, not CD (Continuous
Deployment). It validates your code on every push/PR. It does **not** deploy anything to
AWS.

**Why doesn't this workflow deploy anything?** KodeKloud AWS Playground credentials are
temporary sandbox credentials that rotate every session — the wrong kind of credential to
store as a long-lived GitHub Actions secret by default. So `ci.yml` deliberately stays
credential-free and safe to run on every single push, with no setup at all. If you *do* want
push-to-deploy, it's available as a separate, explicitly opt-in workflow — see "Extending it"
below.

## What the pipeline actually checks

| Job | What it validates |
|---|---|
| `validate-terraform` | `terraform validate` on `terraform-docker/`, `terraform-docker/backend/`, and `terraform-eks/` — catches typos, missing arguments, and type errors in any `.tf` file, without needing real AWS credentials (`-backend=false`) |
| `build-docker-images` | Builds the backend and frontend Docker images, and validates `docker-compose.yml` — catches Dockerfile mistakes before you ever touch AWS |
| `lint-shell-scripts` | Runs [ShellCheck](https://www.shellcheck.net/) against every script in `scripts/` — catches common bash mistakes (unquoted variables, unreachable code, etc.) |
| `validate-kubernetes-manifests` | Runs [kubeconform](https://github.com/yannh/kubeconform) against every file in `kubernetes/` (the optional Level 2 manifests) — catches invalid Kubernetes YAML |

All four jobs run in parallel and need nothing but a checkout — no AWS credentials, no
Docker registry credentials, no secrets configured in your repo at all.

## Using it

1. Push this project to your own GitHub repository (a plain `git init` + `git remote add` +
   `git push` — no special setup)
2. Open the **Actions** tab on GitHub — the workflow runs automatically on every push to
   `main` and every pull request
3. A green checkmark means: your Terraform is syntactically valid, your Docker images build,
   your shell scripts pass linting, and your Kubernetes manifests are valid — all *before*
   you spend any KodeKloud session time deploying

## What this teaches

- The difference between CI and CD, and why "just add CD" isn't always the right call for a
  given environment
- Running Terraform/Docker/kubectl-adjacent tooling in a CI runner without cloud credentials
- Using linters (ShellCheck, kubeconform) as an automated first pass before human review
- Structuring a pipeline as independent, parallel jobs instead of one long sequential script

## Extending it (if you want to go further)

**You don't have to extend it yourself — this project now includes an optional, opt-in CD
pipeline.** Running `./scripts/advanced/06-setup-cicd.sh` pushes this project to your own
GitHub repo and enables `.github/workflows/cd.yml`, which applies changes to whichever
infrastructure you already deployed (Docker/EC2 or Kubernetes/EKS) on every push to `main`.
See **[docs/16-cicd-continuous-deployment.md](16-cicd-continuous-deployment.md)** for the full
walkthrough, including the important caveat about KodeKloud's session-scoped credentials and
how this differs from a real, long-lived AWS account setup (OIDC federation, no static keys).
