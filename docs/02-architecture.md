# 2. Architecture

## High-level diagram

```
Your Browser
     │
     ▼
http://<EC2_PUBLIC_IP>                (Route: Internet Gateway → Public Subnet → EC2)
     │
┌────────────────────────────────────────────────────┐
│  EC2 Instance — t3.medium, Ubuntu 22.04, single AZ   │
│                                                      │
│  Docker Engine (installed by user_data.sh)          │
│   ├── thermos-frontend   Nginx, serves React build   │
│   │      listens on :80                              │
│   ├── thermos-backend    Flask API                   │
│   │      listens on :5000                            │
│   └── thermos-postgres   PostgreSQL 16                │
│          listens on :5432 (container-internal only)  │
│                                                      │
│  All three containers share one Docker bridge        │
│  network (`thermos-net`) defined in                  │
│  docker-compose.yml                                  │
└────────────────────────────────────────────────────┘
     ▲
[AWS Security Group: thermos-sg]
 ├─ 22   SSH    0.0.0.0/0   (admin access — restrict in real use)
 ├─ 80   HTTP   0.0.0.0/0   (frontend)
 ├─ 443  HTTPS  0.0.0.0/0   (reserved, unused today)
 └─ 5000 HTTP   0.0.0.0/0   (backend API, for debugging)
```

## AWS resources created by `terraform-docker/main.tf`

| Resource | Purpose |
|---|---|
| `aws_vpc.thermos` | Isolated network, `10.0.0.0/16` |
| `aws_subnet.public` | Single public subnet in `us-east-1a`, `10.0.1.0/24` |
| `aws_internet_gateway.thermos` | Gives the VPC internet access |
| `aws_route_table.public` + association | Routes `0.0.0.0/0` traffic through the gateway |
| `aws_security_group.thermos` | Firewall rules (see table above) |
| `data.aws_ami.ubuntu` | Looks up the latest Ubuntu 22.04 AMI at apply-time |
| `tls_private_key.thermos` + `aws_key_pair.thermos` | Auto-generated SSH key pair, so SSH access works with zero manual setup |
| `local_file.private_key_pem` | Saves the private key to `terraform-docker/thermos-key.pem` locally |
| `aws_instance.thermos` | The `t3.medium` EC2 instance itself, boots with `user_data.sh`, and receives your code via a `file` provisioner |

No NAT gateway, no private subnet, no load balancer, no multi-AZ — the public subnet and a
single instance are enough for a workshop-scale deployment and keep the project inside
[KodeKloud AWS Playground limits](03-kodekloud-aws-playground-limits.md).

## Boot sequence (`terraform-docker/user_data.sh`)

When the EC2 instance boots for the first time, `user_data.sh` runs automatically as root,
at the same time Terraform is uploading your code to it (see below):

1. Updates apt packages, installs `curl`, `git`, `wget`
2. Installs Docker Engine + the Docker Compose plugin from Docker's official apt repo
3. Adds the `ubuntu` user to the `docker` group
4. Waits for `docker-compose.yml` and `src/` to appear in `/home/ubuntu/thermos` — these are
   uploaded directly by Terraform's `file` provisioner (`main.tf`), not cloned from a git
   repository
5. Runs `docker compose build` and `docker compose up -d`
6. Polls each service's health endpoint and prints the final URLs

All output is logged to `/var/tmp/thermos-setup.log` on the instance — see
[07-troubleshooting.md](07-troubleshooting.md) if something doesn't come up.

## Local development stack (`docker-compose.yml`)

The same three services run locally, defined in the project-root `docker-compose.yml`:

```
postgres  → backend (depends_on, waits for healthcheck) → frontend (depends_on, waits for healthcheck)
```

- `postgres`: official `postgres:16-alpine` image, seeded from `src/database/init.sql`
- `backend`: built from `src/backend/Dockerfile.dev` (hot-reload friendly for local dev)
- `frontend`: built from `src/frontend/Dockerfile` (Nginx serving a production React build)

Run it with `./scripts/02-validate.sh` (see
[05-local-validation.md](05-local-validation.md)) before deploying to AWS.

## Why this design?

- **One EC2 instance, not Kubernetes:** freshers can SSH in and see exactly what's running —
  `docker compose ps`, `docker compose logs` — with nothing hidden behind a scheduler.
- **Docker Compose locally and on the instance:** the exact same `docker-compose.yml`
  definitions run in both places, so "it worked on my machine" reliably means "it'll work on
  EC2" too.
- **Single Terraform file:** every resource is visible in one place, which matters more for
  learning than for scale.
