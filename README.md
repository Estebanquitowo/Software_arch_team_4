# Software Architecture - Team 4 (Rails + MongoDB)

Book review web application built with:

* Ruby 4.0.6
* Rails 8.1.3.1
* MongoDB 8.0
* [Mongoid](https://www.mongodb.com/docs/mongoid/current/quick-start-rails/) 9.1

## Prerequisites

* If on Windows 11:
    * WSL2 is needed, with Ubuntu>=24.04 LTS
    * Docker Desktop installed and running on Windows 11 (with WSL2 integration enabled).

## Deployment Options

This project supports two deployment methods that run the same application images (`Dockerfile.dev` / `Dockerfile.production`). Use one method at a time; both expose the application at `http://localhost:3000`.

**Docker Compose** (`docker-compose.yml`): Starts `web` and `mongodb` as containers on the local machine. Suitable for simple local development. Container restarts are manual and data is stored in the Docker volume `mongodb_data`.

**Kubernetes** (`k8s/` manifests with `k3d`): Runs the same Docker images as Kubernetes workloads inside a lightweight `k3d` (K3s in Docker) cluster. The manifests provide:

*   **Deployment** — maintains the desired replica count and automatically recreates pods after deletion or failure
*   **Service** — provides stable in-cluster DNS (`web`, `mongodb`) and exposes the application via `ClusterIP` with `port-forward`
*   **PersistentVolumeClaim** — stores MongoDB data on `local-path` storage so data persists across pod restarts
*   **ConfigMap / Secret** — injects configuration (`MONGODB_URI`, `RAILS_ENV`) and credentials (`HARDCOVER_API_TOKEN`, `SECRET_KEY_BASE`) at runtime without baking them into the image
*   **Rancher** — optional management UI for the existing `k3d` cluster. No Rancher manifests are included; import the cluster with `k3d kubeconfig get dev` via Rancher's *Import Existing* workflow. See `k8s/README.md` for details.

## Local Development — Option A: Docker Compose (simplest)

1. Clone the repository and enter the directory:
    ```sh
    git clone https://github.com/Estebanquitowo/Software_arch_team_4
    cd Software_arch_team_4
    ```

1. Start the application stack:
    ```sh
    docker compose up -d --build
    ```

    The web server (service="web") will be accessible at http://localhost:3000. \
    The local MongoDB instance (service="mongodb") will run on port 27017.

1. Verify containers are running:
    ```sh
    docker compose ps
    ```

1. If running the app for the first time, populate it with:
    ```sh
    docker compose exec web bin/rails db:seed
    ```

    In order of populating the database, `seeds.rb` uses a [Hardcover.app](https://hardcover.app) API token. To obtain one:
    
    1. Create a Hardcover account.
    1. Go to the [account](https://hardcover.app/account/api) section inside the site.
    1. Copy the text block starting with the `'Bearer'` line, without including it; this is the API token.
    1. Copy `.env.example`, paste it on root, rename it to `.env`, and paste the API token as the value for the `HARDCOVER_API_TOKEN` key.

## Local Development — Option B: Kubernetes with k3d + Rancher (1-2 commands)

Isolated manifests in `k8s/` — does not modify `Dockerfile*`, `docker-compose.yml`, or app code. See `k8s/README.md` for full manual details.

### Prerequisites
```sh
docker --version
kubectl version --client  # install: curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
k3d version               # install: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

### Quick start
```sh
bin/k8s-up   # builds image, creates k3d cluster if needed, imports image, creates secrets, applies manifests
```

View the application (requires an extra terminal — `ClusterIP` is internal, unlike Docker Compose ports):

```sh
# In a separate terminal, keep this running:
kubectl -n software-arch-team4 port-forward svc/web 3000:80
# Then open http://localhost:3000 or: curl -i http://localhost:3000/up  # expect 200
```

Stop the port redirection: `Ctrl+C` in the port-forward terminal (or `kill %1` / `jobs` then `kill` if run with `&`).

Stop / cleanup:
```sh
bin/k8s-down          # deletes manifests (keeps cluster)
k3d cluster delete dev # full cleanup
```

### Manual steps (what `bin/k8s-up` does)
```sh
# From repository root
docker build -f Dockerfile.dev -t software_arch_team_4:k8s .
k3d cluster create dev --port "30080:80@loadbalancer"  # skip if already exists
k3d image import software_arch_team_4:k8s -c dev
```

### 2. Create namespace and secrets (not committed)
`k8s/secret.yaml` is a template excluded from kustomize. Create the real secret imperatively:
```sh
kubectl apply -f k8s/namespace.yaml
kubectl -n software-arch-team4 create secret generic app-secret \
  --from-literal=HARDCOVER_API_TOKEN="$(grep HARDCOVER_API_TOKEN .env 2>/dev/null | cut -d= -f2)" \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  --dry-run=client -o yaml | kubectl apply -f -
# Production variant: add --from-literal=RAILS_MASTER_KEY="$(cat config/master.key)" and set ConfigMap RAILS_ENV=production
```

### 3. Deploy
```sh
kubectl apply -k k8s/
kubectl -n software-arch-team4 get pods,svc,pvc,cm,secret
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 wait --for=condition=available deployment/web --timeout=120s
```

### 4. Verify (required by assignment)
```sh
# a) Reachable through Service
kubectl -n software-arch-team4 port-forward svc/web 3000:80 &
curl -i http://localhost:3000/up   # expect 200

# b) Self-healing: pod recreated automatically
kubectl -n software-arch-team4 delete pod -l app=web
kubectl -n software-arch-team4 get pods   # new pod Running
curl -i http://localhost:3000/up          # still 200

# c) PVC survives restart
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.insertOne({check:"before-restart"})'
kubectl -n software-arch-team4 delete pod -l app=mongodb
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.findOne({check:"before-restart"})' # still exists
```

### 5. Cleanup
```sh
bin/k8s-down             # or kubectl delete -k k8s/
k3d cluster delete dev
```

### 6. Rancher Integration

Rancher is an optional management UI for the `k3d` cluster and is **not** started by `bin/k8s-up`. `bin/k8s-up` only creates the `k3d` cluster, builds/imports the image, and applies the `k8s/` manifests. To use Rancher, start it manually as a standalone Docker container and import the existing cluster.

The repository does not include Rancher manifests. Rancher imports the existing cluster and visualizes the Kubernetes objects defined in `k8s/` (`Deployment/web`, `Service/web`, `PVC/mongodb-data`). The cluster can be verified either through Rancher or directly with `kubectl`.

```sh
# Start Rancher (once, if not already running)
docker run -d --privileged --restart=unless-stopped -p 443:443 --name rancher rancher/rancher

k3d kubeconfig get dev > /tmp/kubeconfig-dev.yaml
# Rancher UI → https://localhost:443 (set admin password)
# → Add Cluster → Import Existing → copy the generated kubectl apply URL
# → run it against the kubeconfig: KUBECONFIG=/tmp/kubeconfig-dev.yaml kubectl apply -f <import-url>
# → the namespace software-arch-team4 with all pods, services and PVCs becomes visible in Rancher
```

### 7. Stopping Rancher

Rancher runs as a standalone Docker container (`rancher/rancher`) and is not removed by `bin/k8s-down` or `k3d cluster delete`. It continues running in the background on `https://localhost:443`.

```sh
# Check if Rancher is running (shows name like "rancher" or auto-generated "competent_aryabhata")
docker ps --filter ancestor=rancher/rancher

# Stop and remove (works for any name, 1-2 commands)
docker rm -f $(docker ps -q --filter ancestor=rancher/rancher)
# Or by explicit name (replace with the name from docker ps):
# docker stop rancher && docker rm rancher
# docker stop competent_aryabhata && docker rm competent_aryabhata
```

## Workflow & Development Commands

Development can be done inside the Docker Containers. Effects of Rails and database commands ran inside them should persist even after containers are down. Commands ran this way must be prefixed with the `docker compose exec` string, as in all following examples.

### Database & Seeding
```sh
# Populate database with seed data
docker compose exec web bin/rails db:seed

# KEY DEBUGGING COMMAND: Access interactive MongoDB shell (mongosh)
docker compose exec mongodb mongosh
```

### Generators & Rails Console
```sh
# Open Rails interactive console
docker compose exec web bin/rails c

# Generate scaffolds (includes views, model and controller; essentialy batteries-included CRUD)
docker compose exec web bin/rails g scaffold Book title:string summary:text # remaining fields...
```

### Tests
```sh
# Run the test suite (connects to the test database in the mongodb container)
docker compose exec web bin/rails test
```

### Viewing Logs
```sh
# View live web application logs
docker compose logs -f web

# View live MongoDB container logs (not very useful xd)
docker compose logs -f mongodb
```

(Press Ctrl + C to exit log streams without stopping containers).

### Stopping & Rebuilding
```sh
# Stop containers (preserves database data)
docker compose down

# Rebuild containers (run whenever Gemfile or Dockerfile changes)
docker compose up -d --build

# Stop containers and wipe local database volumes (fresh start)
docker compose down -v
```
