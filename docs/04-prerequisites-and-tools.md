# 4. Prerequisites and Tool Setup

You need four tools on your local machine (or KodeKloud terminal): **git**, **Terraform**
(>= 1.0), **AWS CLI v2**, and **Docker** (optional locally, but required conceptually since
it's what runs on the EC2 instance).

## Fastest option: `scripts/01-setup.sh` (new)

```bash
chmod +x scripts/01-setup.sh
./scripts/01-setup.sh
```

What makes it faster than doing this by hand:

- Detects what's already installed and **skips it** — safe to re-run anytime
- Installs Docker, Terraform, AWS CLI v2, git, and jq in a single pass on Linux (apt-based)
  or macOS (Homebrew)
- Uses official install scripts/repos (Docker's `get.docker.com`, HashiCorp's apt repo, AWS's
  official installer) instead of slower manual multi-step instructions
- Starts and enables the Docker daemon, and adds your user to the `docker` group
  automatically
- Prints a clear ✅ / ❌ summary at the end so you know immediately if anything needs
  attention

## Configure AWS credentials (required either way)

```bash
aws configure
# AWS Access Key ID:     <from your KodeKloud AWS Playground session>
# AWS Secret Access Key: <from your KodeKloud AWS Playground session>
# Default region name:   us-east-1
# Default output format: json

aws sts get-caller-identity
```

If `aws sts get-caller-identity` fails, your credentials weren't saved correctly — re-run
`aws configure` and double check you copied the keys without extra whitespace.

## Manual installation (per OS), if you'd rather not use a script

<details>
<summary>Git</summary>

- **Windows:** https://git-scm.com/download/win, or `choco install git -y`
- **macOS:** `brew install git`
- **Linux:** `sudo apt update && sudo apt install git -y`
</details>

<details>
<summary>Terraform (>= 1.0)</summary>

- **Windows:** download from https://www.terraform.io/downloads, extract to a folder, add
  that folder to `PATH`; or `choco install terraform -y` / `scoop install terraform`
- **macOS:** `brew install terraform`
- **Linux:**
  ```bash
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform -y
  ```
</details>

<details>
<summary>AWS CLI v2</summary>

- **Windows:** MSI installer from https://aws.amazon.com/cli/, or `choco install awscli -y`
- **macOS:** `brew install awscli`, or the official `.pkg` installer
- **Linux:**
  ```bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  ```
</details>

<details>
<summary>Docker (optional, for local testing before deploying)</summary>

- **Windows/macOS:** Docker Desktop from https://www.docker.com/products/docker-desktop
- **Linux:** installed automatically by `01-setup.sh`
</details>

## Docker daemon not running?

```bash
# Linux:
sudo systemctl start docker
sudo systemctl status docker

# Windows/macOS:
# Open Docker Desktop and wait until it reports "Docker is running"
```

If it still won't start, re-run `./scripts/01-setup.sh` — it re-checks and re-enables the
Docker service. After first install, log out and back in for the `docker` group membership
to take effect (so you can run `docker` without `sudo`).
