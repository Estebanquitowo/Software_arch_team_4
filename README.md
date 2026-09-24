# Software Architecture - Team 4 (Rails + MongoDB)

Book review web application built with:

* Ruby 4.0.6
* Rails 8.1.3.1
* MongoDB 8.0
* [Mongoid](https://www.mongodb.com/docs/mongoid/current/quick-start-rails/) 9.1

## Prerequisites

### General Prerequisites

* If on Windows 11:
    * WSL2 is needed, with Ubuntu>=24.04 LTS
    * Docker Desktop installed and running on Windows 11 (with WSL2 integration enabled).

### For Database Populating

In order of populating the database, `seeds.rb` uses a [Hardcover.app](https://hardcover.app) API token. To obtain one:

1. Create a Hardcover account.
1. Create and copy a [new API key](https://hardcover.app/account/api/keys/new) by:
    1. Giving it any name;
    1. And granting the necessary permissions to the Key by checking the `read:catalog` box inside the ***Permissions*** section.
1. Copy `.env.example`, paste it on root, rename it to `.env`, and paste the API token as the value for the `HARDCOVER_API_TOKEN` key.

### For Kubernetes Deployment

```sh
docker --version
kubectl version --client  # install: curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
k3d version               # install: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

## Deployment Options

This project supports two deployment methods that run the same application images (`Dockerfile.dev` / `Dockerfile.production`). Use one method at a time.

**Docker Compose**: Starts `web` and `mongodb` plus optional `redis`/`meilisearch` and `haproxy` on the local machine. Suitable for simple local development. Container restarts are manual and data is stored in Docker volumes (`mongodb_data`, `image_data`).

* Baseline `docker-compose.yml` (no proxy) exposes the app at `http://localhost:3000` for backward compatibility.
* Proxy-enabled files (`docker-compose.proxy.yml`, `docker-compose.full.yml`, `docker-compose.scale.yml`) expose HAProxy at `http://app.localhost` (`:80`) and `https://app.localhost` (`:443`) — TLS terminates at HAProxy, `web` is not directly exposed (`expose: 3000` only).

**Kubernetes** (`k8s/` manifests with `k3d`): Runs the same Docker images as Kubernetes workloads inside a lightweight `k3d` (K3s in Docker) cluster. The manifests provide:

*   **Deployment** — maintains the desired replica count and automatically recreates pods after deletion or failure
*   **Service** — provides stable in-cluster DNS (`web`, `mongodb`) and exposes the application via `ClusterIP` with `port-forward`
*   **PersistentVolumeClaim** — stores MongoDB data on `local-path` storage so data persists across pod restarts
*   **ConfigMap / Secret** — injects configuration (`MONGODB_URI`, `RAILS_ENV`) and credentials (`HARDCOVER_API_TOKEN`, `SECRET_KEY_BASE`) at runtime without baking them into the image
*   **Rancher** — optional management UI for the existing `k3d` cluster. No Rancher manifests are included; import the cluster with `k3d kubeconfig get dev` via Rancher's *Import Existing* workflow. See `k8s/README.md` for details.

  Like Docker Compose, Kubernetes provides **5 variants** via kustomize base + overlays (`bin/k8s-up [base|cache|search|full|edge]`). The `edge` variant adds HAProxy in front of the stable `web` Service, with Redis and Meilisearch enabled.

### Reverse Proxy (HAProxy)

`haproxy/` is an isolated module (no app code changes). It provides:

* **Edge entrypoint:** `haproxy:3.0-alpine` with `frontend http_front` binding `*:80` and `*:443 ssl crt /usr/local/etc/haproxy/certs/self-signed.pem`. TLS is terminated at the proxy, `web` speaks plain HTTP (`3000`).
* **Custom domain:** ACL `host_app hdr(host) -i app.localhost localhost` — app is served under `app.localhost` (`*.localhost` resolves to `127.0.0.1` via systemd-resolved). Requests with other `Host` are `403`.
* **Static at edge:** `image_data:/data/images:ro` mounted to HAProxy, `acl is_images/is_assets` + `cache static_cache` (`total-max-size 128`, `max-object-size 10M`, `max-age 86400`). Rails is the origin on a first miss; HAProxy stores a successful response and later requests are served at the edge (`<CACHE>` in logs, `Age` header). `SERVE_STATIC=true` remains enabled so cache misses are valid.
* **Load balancing:** `docker-compose.scale.yml` runs `web` with `deploy: replicas: 3` (Compose v2, no Swarm) + `resolvers docker (127.0.0.11:53)` + `server-template web 3 web:3000 resolvers docker ... check` `balance roundrobin`. Explicit `web1/web2/web3` fallback is documented in `haproxy.scale.cfg`. Health checks are `GET /up` with `Host: localhost`.
* **Certs:** `haproxy/certs/self-signed.pem` (crt+key) generated for `app.localhost`. See *HTTPS* below.

## Local Development and Deployment 

### Option A: Docker Compose (6 variants — app works with or without cache/search/proxy/scale)

The app implements **optional** components via Strategy pattern:

* **Cache:** `Redis` (`redis:7-alpine`) with `Rails.cache = :redis_cache_store`. If `REDIS_URL` unreachable/missing → gracefully falls back to `:memory_store` (`CacheService.fetch` rescues and yields directly, so requests never 500).
* **Search:** `Meilisearch` (`getmeili/meilisearch:v1.12`) with `meilisearch-rails`. If `MEILISEARCH_URL` unreachable/missing → gracefully falls back to native MongoDB regex/`$text` search (`SearchService`).
* **Uploads:** book covers and author images are stored under `IMAGE_STORAGE_PATH` (default `/data/images`; the compose files mount a shared `image_data` volume there) and served at `/images/<relative>` by `ImagesController`. In multi-instance deployments all instances must share this storage path.
* **Static assets:** the app serves `public/` files and `/images/*` uploads as the origin (`SERVE_STATIC=true`). With HAProxy, clients still access those paths through the edge; HAProxy caches successful static responses without contacting Rails on a hit.
* **Proxy:** `haproxy:3.0-alpine` terminates TLS, enforces `app.localhost` ACL, and proxies to `web:3000` with health `GET /up`. See `haproxy/haproxy.cfg` (single) and `haproxy/haproxy.scale.cfg` (3× via `resolvers docker` + `server-template`).
* **Hosts:** Rails `config.hosts` now allows `app.localhost`, `web`, `haproxy`, `*.localhost` for HAProxy health checks and custom domain (see `config/environments/development.rb`).

Compose files:

| File | Services | Env / Ports | Purpose |
|------|----------|-------------|---------|
| `docker-compose.yml` | `web` + `mongodb` | `CACHE_ENABLED=false` `SEARCH_ENABLED=false` `SERVE_STATIC=true` — `web 3000:3000` | **Baseline, no proxy** — backward compat `http://localhost:3000` |
| `docker-compose.cache.yml` | + `redis` | `CACHE_ENABLED=true` `SERVE_STATIC=true` — `3000:3000` | Cache only, no proxy |
| `docker-compose.search.yml` | + `meilisearch` | `SEARCH_ENABLED=true` `SERVE_STATIC=true` — `3000:3000` | Search only, no proxy |
| `docker-compose.proxy.yml` | `web`+`mongodb`+`haproxy` | `SERVE_STATIC=true` — `web expose:3000`, `haproxy 80:80 443:443` | **App+DB+Proxy** (Phase 9) |
| `docker-compose.full.yml` | `web`+`mongodb`+`redis`+`meilisearch`+`haproxy` | `CACHE/SEARCH=true` `SERVE_STATIC=true` — `haproxy 80:80 443:443` | **Full + Proxy** (Phase 10) |
| `docker-compose.scale.yml` | `web×3`+`mongodb`+`redis`+`meilisearch`+`haproxy` | `replicas:3` + `server-template 3` `SERVE_STATIC=true` — `haproxy 80:80 443:443` | **×3 + LB + Cache + Search** (Phase 11) |

> **Port strategy:** Baseline keeps `3000:3000` so `docker compose up` and old docs still work. Proxy-enabled files deliberately remove the host port from `web` (`expose: 3000` only) and bind HAProxy to standard edge ports `80:80` + `443:443`. `https://app.localhost:3000` is intentionally not used — edge should be `https://app.localhost` (or `http://localhost` for quick test).

Usage (pick one):

```sh
# 1) Baseline — no proxy, http://localhost:3000
docker compose -f docker-compose.yml up -d --build

# 2) Cache only (no proxy)
docker compose -f docker-compose.cache.yml up -d --build

# 3) Search only (no proxy)
docker compose -f docker-compose.search.yml up -d --build

# 4) Proxy — App + DB + HAProxy (http://app.localhost / https://app.localhost)
docker compose -f docker-compose.proxy.yml up -d --build

# 5) Full + Proxy — with cache & search
docker compose -f docker-compose.full.yml up -d --build

# 6) Scale — App×3 + DB + HAProxy LB + Cache + Search (roundrobin, health checks)
docker compose -f docker-compose.scale.yml up -d --build
# also: docker compose -f docker-compose.scale.yml up -d --scale web=3  # explicit fallback
```

Scale notes: `web` uses `deploy: replicas: 3` (Compose v2, no Swarm). HAProxy discovers all 3 via `resolvers docker` (`127.0.0.11:53`) + `server-template`. `tmpfs: /rails/tmp/pids` + `rm -f tmp/pids/server.pid` avoids `server.pid` collision on shared `.:/rails` volume.

Common steps after `up`:

```sh
docker compose -f <chosen-file> ps
# for proxy/full/scale the app is behind HAProxy (80/443), not localhost:3000:
curl -i http://app.localhost/up           # or: curl -i http://localhost/up
curl -ik https://app.localhost/up         # TLS self-signed, use -k
# for baseline/cache/search the app is still http://localhost:3000:
curl -i http://localhost:3000/up
# seed / reindex (pick one, matches compose -f)
docker compose -f <chosen-file> exec web bin/rails db:seed   # also triggers Meilisearch reindex if enabled + clears cache
# or for scale with replicas (exec picks one): docker exec software_arch_team_4-web-1 bin/rails db:seed
# optional explicit reindex/clear:
docker compose -f <chosen-file> exec web bin/rails search:reindex
docker compose -f <chosen-file> exec web bin/rails cache:clear
```

> **Note:** the search/full/scale compose files use `http://127.0.0.1:7700/health` for the Meilisearch healthcheck (not `localhost`) because `wget` resolves `localhost` to IPv6 `[::1]`, which Meilisearch doesn't listen on — that made `up` fail with "dependency ... is unhealthy".

### HTTPS / TLS (self-signed, terminated at HAProxy)

Cert is already committed at `haproxy/certs/self-signed.pem` (`app.localhost.crt` + `app.localhost.key`). To regenerate:

```sh
mkdir -p haproxy/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout haproxy/certs/app.localhost.key -out haproxy/certs/app.localhost.crt \
  -subj "/CN=app.localhost" -addext "subjectAltName=DNS:app.localhost,DNS:localhost,IP:127.0.0.1"
cat haproxy/certs/app.localhost.crt haproxy/certs/app.localhost.key > haproxy/certs/self-signed.pem
chmod 644 haproxy/certs/self-signed.pem haproxy/certs/app.localhost.crt
# HAProxy loads it via: bind *:443 ssl crt /usr/local/etc/haproxy/certs/self-signed.pem
```

`haproxy` mounts `haproxy/certs:ro` and `image_data:/data/images:ro`. Rails remains the cache-miss origin; HAProxy caches `/images/*`/`/assets/*` after the first 200 response.

Custom domain: `app.localhost` resolves to `127.0.0.1` via `systemd-resolved` (no `/etc/hosts` edit needed on Ubuntu/WSL). HAProxy enforces it:

```sh
curl -i http://app.localhost/up           # 200
curl -i -H "Host: evil.com" http://127.0.0.1:80/up  # 403
# explicit resolve without DNS:
curl -i --resolve app.localhost:80:127.0.0.1 http://app.localhost/up
curl -ik --resolve app.localhost:443:127.0.0.1 https://app.localhost/up
```

Browsers will warn on self-signed; use `curl -k` or import `haproxy/certs/app.localhost.crt` as trusted.

### Verify HAProxy (proxy/full/scale)

Pick a proxy-enabled file (`proxy`, `full`, or `scale`). Example with `proxy`:

```sh
docker compose -f docker-compose.proxy.yml up -d --build
docker compose -f docker-compose.proxy.yml ps # haproxy + web (expose only) + mongodb
# 1) Edge health
curl -i http://localhost/up                    # 200 via haproxy :80
curl -ik https://app.localhost/up             # 200 via haproxy :443 (TLS)
# 2) Web not directly exposed
curl -i http://localhost:3000/up              # Connection refused -> expected
# 3) Host ACL
curl -i -H "Host: evil.com" http://127.0.0.1:80/up # 403
# 4) Static at edge (first MISS -> backend, second HIT -> cache, Age header)
curl -i http://localhost/icon.svg  # then:
curl -i http://localhost/icon.svg # -> <CACHE> in haproxy logs, Age: 0
docker logs software_arch_haproxy | grep icon.svg
# 5) Uploaded images via shared volume (Rails origin on miss, HAProxy cache)
# create an image via UI http://app.localhost/books/new or via runner, then:
curl -i http://localhost/images/books/<file>.png
docker logs software_arch_haproxy | grep images # 1 backend, next -> <CACHE>
# 6) Dynamic still proxied
curl -i http://app.localhost/books            # 200 via app_backend/web
docker logs software_arch_haproxy | grep "GET /books"
```

For `scale`, additionally:

```sh
docker compose -f docker-compose.scale.yml up -d --build
docker compose -f docker-compose.scale.yml ps # web-1/2/3 + haproxy
for i in {1..10}; do curl -s --resolve app.localhost:80:127.0.0.1 http://app.localhost/up >/dev/null; done
docker logs software_arch_haproxy | grep "GET /up" | tail # shows web1/web2/web3 roundrobin
# failure
docker stop software_arch_team_4-web-1; sleep 8
for i in {1..6}; do curl -s http://localhost/up >/dev/null; done
docker logs software_arch_haproxy | tail # only web2/web3
docker start software_arch_team_4-web-1; sleep 12 # back to 3
```

Validate HAProxy configs without booting:

```sh
docker run --rm -v $PWD/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v $PWD/haproxy/certs:/usr/local/etc/haproxy/certs:ro haproxy:3.0-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg && echo ok
docker run --rm -v $PWD/haproxy/haproxy.scale.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro -v $PWD/haproxy/certs:/usr/local/etc/haproxy/certs:ro haproxy:3.0-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg && echo ok
```

1. Clone the repository and enter the directory:
    ```sh
    git clone https://github.com/Estebanquitowo/Software_arch_team_4
    cd Software_arch_team_4
    ```

1. Start the application stack (example: full variant — now behind HAProxy):
    ```sh
    docker compose -f docker-compose.full.yml up -d --build
    ```

    For `docker-compose.full.yml` (proxy-enabled) HAProxy is the edge: app at `http://app.localhost` (`:80`) and `https://app.localhost` (`:443`), `web` is not exposed on `:3000` (`expose` only). For baseline `docker-compose.yml` the app remains at `http://localhost:3000`. \
    MongoDB always on `127.0.0.1:27017`.

1. Verify containers are running:
    ```sh
    docker compose -f docker-compose.full.yml ps
    ```

1. If running the app for the first time, populate it with:
    ```sh
    docker compose -f docker-compose.full.yml exec web bin/rails db:seed
    ```

### Option B: Kubernetes with k3d

The app implements **optional** cache (Redis) and search (Meilisearch) components via its Strategy pattern. Just like Docker Compose, Kubernetes offers **4 standalone variants** using kustomize overlays — all share the same `base` (web + mongodb):

| Command | Variant | Extra services | Env |
|---------|---------|----------------|-----|
| `bin/k8s-up base` (default) | as-is | — | `CACHE_ENABLED=false` `SEARCH_ENABLED=false` |
| `bin/k8s-up cache` | + Redis | `redis` | `CACHE_ENABLED=true` |
| `bin/k8s-up search` | + Meilisearch | `meilisearch` | `SEARCH_ENABLED=true` |
| `bin/k8s-up full` | + Redis + Meilisearch | `redis`, `meilisearch` | both enabled |

Isolated manifests in `k8s/` (base + overlays) — does not modify `Dockerfile*`, `docker-compose.yml`, or app code. See `k8s/README.md` for full manual details.

1. Generate the k3d cluster (default `base` variant; pass `cache`, `search`, or `full` for the others):
    ```sh
    bin/k8s-up            # as-is: web + mongodb
    # bin/k8s-up cache    # + Redis
    # bin/k8s-up search   # + Meilisearch
    # bin/k8s-up full     # + Redis + Meilisearch
    ```
    This builds the image, creates the k3d cluster if needed, imports the image, creates secrets, applies the overlay manifests, and **runs `db:seed` automatically** (which reindexes Meilisearch and clears cache when those features are enabled).

1. View the application (requires an extra terminal):
    ```sh
    # In a separate terminal, keep this running:
    kubectl -n software-arch-team4 port-forward svc/web 3000:80
    # Then open http://localhost:3000 or: curl -i http://localhost:3000/up  # expect 200
    ```

1. Stop the port redirection: `Ctrl+C` in the port-forward terminal (or `kill %1` / `jobs` then `kill` if run with `&`).

1. Stop / cleanup the cluster:
    ```sh
    bin/k8s-down            # deletes manifests (match the overlay you started, keeps cluster)
    bin/k8s-down full       # example: delete from the full overlay
    k3d cluster delete dev  # full cleanup
    ```

## Running Load Tests & Benchmarks

This repository includes a benchmark suite using [Grafana k6](https://k6.io/) to measure response latencies ($p50$, $p95$), request throughput, container resource usage (CPU/memory), and OS thread counts across both single-instance and horizontally scaled deployments.

### Prerequisites & Setup

1. **Seed Database and Search Engine:**
    Ensure MongoDB and Meilisearch contain test data:
    ```sh
    docker compose -f docker-compose.full.yml up -d
    docker compose -f docker-compose.full.yml exec web bin/rails db:seed
    docker compose -f docker-compose.full.yml exec web bin/rake search:reindex
    ```

1. **Upload a Test Image (Required for Static Asset Benchmark):**
    Default seed records do not include cover or author images. Before executing the static asset benchmark, an image must be manually uploaded via the web interface:
    
    1. Open [https://app.localhost](https://app.localhost) in your browser.
    1. Navigate to Books, select any book (e.g., /books/<id>), and click "Edit this book".
    1. Upload an image (.png or .jpg) and save the changes.
    1. On the updated book page, right-click the cover image and copy its image address. The URL structure matches:
        ```sh
        http://app.localhost/images/books/<image_id>.jpg
        ```
    1. Open `benchmark/run_benchmarks_single.sh` and `benchmark/run_benchmarks_scale.sh`, and replace the static URL to match your uploaded image path (line 11 on both):
        ```sh
        "static:https://app.localhost/images/books/<YOUR_IMAGE_ID>.jpg"
        ```

### Executing the Benchmarks

All execution scripts are located in the `benchmark/` directory. Although test have already been ran, you may want to execute them again. It is not neccesary to initialize the docker containers, since both benchmarks do so inside of their bash code.

#### 1. Single-Instance Benchmark (`docker-compose.full.yml`)

Tests all four endpoints across 1, 10, 100, 1,000, and 5,000 request tiers against the single-instance stack:

```sh
chmod +x benchmark/*.sh
./benchmark/run_benchmarks_single.sh
```

Outputs are saved to `benchmark/results/single/`.

#### 2. Scaled 3-Instance Benchmark (`docker-compose.scale.yml`)

Deploys the 3-replica load-balanced architecture and runs the identical 20-run benchmark suite:

```sh
./benchmark/run_benchmarks_scale.sh
```

Outputs are saved to benchmark/results/scaled/.

### Parsing and Viewing Results

To aggregate all output logs into a consolidated Markdown table reporting success rates, average latency, $p95$ tail latency, and peak container CPU utilization, run:

```sh
./benchmark/parse_results.sh
```

To run a single targeted endpoint test manually, use the individual runner script:

```sh
./benchmark/run_benchmarks.sh <name> <target_url> <request_count> [single|scaled]

# Example:
./benchmark/run_benchmarks.sh aggregation "https://app.localhost/reports/top_selling_books" 1000 single
```

## Rancher Integration

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

### Stopping Rancher

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
