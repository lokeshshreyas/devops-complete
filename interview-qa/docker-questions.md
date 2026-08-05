# Docker — Interview Q&A (based on this project)

**Q: In `docker-compose.yml`, why does `backend` have a `depends_on: postgres: condition:
service_healthy` instead of a plain `depends_on: postgres`?**
A: A plain `depends_on` only waits for the container to *start*, not for the service inside
it to be *ready*. Postgres can take a few seconds to finish initializing after the container
starts. `condition: service_healthy` makes Compose wait for the `healthcheck` (a
`pg_isready` command in this project) to pass before starting the backend, avoiding
"connection refused" errors on first boot.

**Q: Why does the backend use `Dockerfile.dev` locally but a different `Dockerfile` in
production/AWS?**
A: The dev image typically enables hot-reload and mounts source code as a volume for fast
iteration, while the production image copies code in at build time and runs a production
WSGI server — smaller, immutable, and faster to start. Compose's `docker-compose.yml` in
this project points at `Dockerfile.dev` for local work; the AWS deployment (via
`user_data.sh`) builds from the repo as checked out, so make sure whichever Dockerfile it
resolves to is the one intended for that environment.

**Q: What does the frontend's `depends_on: backend: condition: service_healthy` protect
against?**
A: Without it, Nginx could start serving the React app before the API it proxies/calls is
ready, causing early requests to fail. Waiting for the backend's health check first avoids
that race condition on cold start.

**Q: Why is `thermos-net` defined explicitly instead of relying on Compose's default
network?**
A: An explicit `bridge` network with a clear name makes container-to-container DNS
resolution (`backend`, `postgres`, `frontend` as hostnames) predictable and makes the setup
easier to reason about when debugging with `docker network inspect thermos-net`.

**Q: The Postgres service publishes port 5432 to the host in `docker-compose.yml` — is that
a problem in production?**
A: For local development it's convenient (you can connect a GUI client to
`localhost:5432`). In the AWS deployment, this project's security group intentionally does
**not** open port 5432 to the internet — only 22, 80, 443, and 5000 are exposed — so
Postgres stays reachable only inside the instance's Docker network, not from the internet.

**Q: What's the difference between `docker compose build` and `docker compose up --build`?**
A: `build` only builds the images. `up --build` builds (if needed) and then starts the
containers in one step. `validate-local.sh` in this project does them separately
(`build --no-cache` then `up -d`) so build failures are reported clearly before any
containers are started.

**Q: Why `--no-cache` in the validation script's build step?**
A: To catch issues that a stale Docker layer cache might otherwise hide — e.g. a
`requirements.txt` change that wouldn't normally invalidate a cached `pip install` layer.
It's slower but more trustworthy for a "does this actually build cleanly" check.
