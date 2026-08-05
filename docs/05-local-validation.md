# 5. Local Validation

Before spending any time on AWS, confirm the app builds and runs correctly on your own
machine with Docker Compose.

## Run it

```bash
chmod +x scripts/02-validate.sh
./scripts/02-validate.sh
```

## What it checks, in order

1. **Docker installation** — confirms `docker --version` works, and that the Docker daemon
   is actually running (tries to start it automatically on Linux if it isn't).
2. **Docker Compose availability** — confirms `docker compose version` works.
3. **Required project files** — checks that `docker-compose.yml`, `src/backend/Dockerfile`,
   `src/frontend/Dockerfile`, `src/database/init.sql`, and `src/backend/app.py` all exist.
4. **Build** — runs `docker compose build --no-cache` for all three services.
5. **Start** — runs `docker compose up -d`.
6. **Wait** — pauses ~30 seconds for Postgres/Flask/Nginx health checks to pass.
7. **(final steps in the script)** — verifies each container is healthy and reachable, then
   tears the stack back down so your machine is left clean.

## Success looks like

```
✅ Docker: Docker version 27.x.x
✅ Docker Compose: Docker Compose version v2.x.x
✅ Found: docker-compose.yml
✅ Found: src/backend/Dockerfile
✅ Found: src/frontend/Dockerfile
✅ Found: src/database/init.sql
✅ Found: src/backend/app.py
✅ Images built successfully
✅ Containers started
```

## If it fails

- **"Docker daemon is not running"** — start Docker Desktop (Windows/macOS) or run
  `sudo systemctl start docker` (Linux), then re-run the script.
- **Build failure** — read the actual `docker compose build` output the script prints; it's
  almost always a missing dependency in `requirements.txt` / `package.json` or a Dockerfile
  typo.
- **Containers start but health checks never pass** — run `docker compose logs` manually
  (from the project root, since that's where `docker-compose.yml` lives) to see what each
  service is complaining about. Common cause: Postgres takes a few extra seconds to
  initialize on first-ever start; the backend's health check retries automatically, so give
  it another 15–20 seconds before assuming something's broken.

## After validation passes

You're clear to deploy to AWS — see [06-terraform-deployment.md](06-terraform-deployment.md)
or just run `./scripts/03-deploy.sh` (or `./scripts/03-deploy.sh` to also automate this
validation step).
