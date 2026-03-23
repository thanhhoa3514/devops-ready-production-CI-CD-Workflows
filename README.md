# Ready Production CI/CD Workflow (NestJS + Docker Hub + VPS)

![CI/CD Workflow Diagram](assets/image.png)

This repository is configured for a production deployment flow:

1. Run tests in GitHub Actions.
2. Build Docker image and push to Docker Hub.
3. Deploy on VPS by pulling image and recreating Docker Compose services.

## Architecture

- App image: `docker.io/<DOCKERHUB_USERNAME>/devops-tutorial:<tag>`
- Production compose file: `docker-compose.prod.yml`
- VPS deploy script: `ops/deploy.sh`
- CI/CD workflows:
  - `.github/workflows/test.yaml`
  - `.github/workflows/build.yaml`
  - `.github/workflows/deploy.yaml`

## Local Development

```bash
pnpm install
pnpm run start:dev
```

## Build and Run Locally with Docker

```bash
docker build -t devops-tutorial:local .
docker run --rm -p 3000:3000 devops-tutorial:local
```

## VPS One-Time Setup

Run once on VPS:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin git
sudo usermod -aG docker "$USER"
newgrp docker
```

Clone project and create production env file:

```bash
git clone <your-repo-url>
cd devops-ready-production-CI-CD-Workflows
cp ops/.env.production.example ops/.env.production
```

Update `ops/.env.production`:

```dotenv
DOCKERHUB_USERNAME=your-dockerhub-username
IMAGE_TAG=latest
APP_PORT=3000
```

Manual deploy on VPS:

```bash
./ops/deploy.sh
```

## GitHub Repository Configuration

Set repository **Variables**:

- `DOCKERHUB_USERNAME`: your Docker Hub username

Set repository **Secrets**:

- `DOCKERHUB_TOKEN`: Docker Hub access token
- `VPS_HOST`: VPS host/IP
- `VPS_USER`: SSH username
- `VPS_SSH_KEY`: private key for SSH login
- `VPS_PORT`: SSH port (optional, default `22`)
- `VPS_APP_DIR`: absolute path to project on VPS

## CI/CD Behavior

### 1) Test Workflow (`test.yaml`)

Runs on push/PR and validates:

- TypeScript type check
- Unit tests
- Coverage

### 2) Build Workflow (`build.yaml`)

Runs on `main`, tags (`v*.*.*`), or manual dispatch.

Actions:

- Run tests
- Build Docker image
- Push tags to Docker Hub:
  - `latest` (default branch)
  - `sha-<commit>`
  - `vX.Y.Z` (when git tag is pushed)

### 3) Deploy Workflow (`deploy.yaml`)

Runs automatically when build workflow succeeds, or manually with an `image_tag` input.

Actions:

- SSH into VPS
- `git pull --ff-only`
- Update `ops/.env.production` with `IMAGE_TAG` and `DOCKERHUB_USERNAME`
- Run `./ops/deploy.sh`:
  - `docker compose pull`
  - `docker compose up -d --remove-orphans --force-recreate`
  - health check wait

## Deployment Commands (Manual)

Deploy latest tag:

```bash
sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=latest/' ops/.env.production
./ops/deploy.sh
```

Deploy specific commit image tag:

```bash
sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=sha-<commit_sha>/' ops/.env.production
./ops/deploy.sh
```

## Notes

- Keep `ops/.env.production` only on VPS. Do not commit real secrets.
- If using a reverse proxy (Nginx/Caddy), map external 80/443 to `APP_PORT`.
