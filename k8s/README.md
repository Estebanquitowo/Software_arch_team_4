# Kubernetes — k3d + Rancher (k3d-only)

Isolated manifests in `k8s/` — does not modify `Dockerfile*`, `docker-compose.yml`, or app code. The manifests are standard Kubernetes resources organized with **kustomize base + overlays**:

* **`k8s/base/`** — web + mongodb (app as-is, `CACHE_ENABLED=false` `SEARCH_ENABLED=false`).
* **`k8s/overlays/cache/`** — base + Redis (`CACHE_ENABLED=true`).
* **`k8s/overlays/search/`** — base + Meilisearch (`SEARCH_ENABLED=true`).
* **`k8s/overlays/full/`** — base + Redis + Meilisearch (both enabled).

Rancher is an optional UI that imports the existing `k3d` cluster — see `## Rancher Integration` after Cleanup.

## Quick start — 1 command

```bash
# From repository root, like docker compose up --build:
#   base (default) | cache | search | full
bin/k8s-up [base]          # as-is: web + mongodb
bin/k8s-up cache           # + Redis
bin/k8s-up search          # + Meilisearch
bin/k8s-up full            # + Redis + Meilisearch
```

View the application (requires an extra terminal — `ClusterIP` is internal):

```bash
# Keep this running in a separate terminal:
kubectl -n software-arch-team4 port-forward svc/web 3000:80
# Then open http://localhost:3000 or: curl -i http://localhost:3000/up  # expect 200
# To stop the redirection, press Ctrl+C in the port-forward terminal (or kill %1 if run with &)
```

`bin/k8s-up` does: `docker build -f Dockerfile.dev -t software_arch_team_4:k8s .` → `k3d cluster create dev` (if missing) → `k3d image import` → create `app-secret` → `kubectl apply -k k8s/overlays/<overlay>` → wait for ready → **`bin/rails db:seed`** (reindexes Meilisearch and clears cache automatically when enabled).

> **Note on seeding:** `db:seed` fetches books from the [Hardcover API](https://hardcover.app/account/api). It **aborts** if `HARDCOVER_API_TOKEN` is missing/invalid (HTTP 401), which is non-fatal for the cluster itself — the app still boots and the `search:reindex` / `cache:clear` steps just won't run. Use `bin/k8s-down <overlay> && bin/k8s-up <overlay>` with a valid token to seed.

Stop: `bin/k8s-down [overlay]` (or `k3d cluster delete dev`).

## 1. Prerequisites

```bash
docker --version
kubectl version --client
k3d version
```

If missing (as on clean CI):
```bash
# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

## 2. Build image and load into cluster (manual — same as bin/k8s-up step 1)

Images are NOT hard-coded with config; ConfigMap/Secret inject at runtime.

```bash
# From repository root
docker build -f Dockerfile.dev -t software_arch_team_4:k8s .
k3d cluster create dev --port "30080:80@loadbalancer" --port "30443:443@loadbalancer"  # skip if exists
k3d image import software_arch_team_4:k8s -c dev

# For production alternative (port 80, thruster):
# docker build -f Dockerfile.production -t software_arch_team_4:k8s .
# and set ConfigMap: RAILS_ENV=production, PORT=80, update web-deployment probes to port 80
```

## 3. Configure secrets (not committed)

`k8s/base/secret.yaml` is a **template** excluded from `kustomization.yaml` to avoid overwriting real secrets.

```bash
kubectl apply -f k8s/base/namespace.yaml

# Development (default): SECRET_KEY_BASE bypasses credentials decryption
kubectl -n software-arch-team4 create secret generic app-secret \
  --from-literal=HARDCOVER_API_TOKEN="$(grep HARDCOVER_API_TOKEN .env 2>/dev/null | cut -d= -f2)" \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  --dry-run=client -o yaml | kubectl apply -f -

# Production alternative (Dockerfile.production, RAILS_ENV=production):
# kubectl -n software-arch-team4 create secret generic app-secret \
#   --from-literal=HARDCOVER_API_TOKEN="..." \
#   --from-literal=RAILS_MASTER_KEY="$(cat config/master.key)" \
#   --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)" \
#   --dry-run=client -o yaml | kubectl apply -f -

# File-based alternative (edit placeholder first):
# kubectl apply -f k8s/base/secret.yaml
```

## 4. Deploy (after secret exists) — pick one of the 4 variants

```bash
# Choose the overlay you want: base | cache | search | full
OVERLAY=base   # or cache / search / full

# Option A: kustomize (secret excluded as above - create it first in step 3)
kubectl apply -k k8s/overlays/$OVERLAY

# Option B: explicit ordered apply for the BASE variant (avoids race)
# (for cache/search/full, prefer Option A so redis/meilisearch manifests apply too)
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/configmap.yaml
# search/full: kubectl apply -f k8s/overlays/search/search-config.yaml
kubectl apply -f k8s/base/mongodb-pvc.yaml
kubectl apply -f k8s/base/mongodb-service.yaml
kubectl apply -f k8s/base/mongodb-deployment.yaml
kubectl apply -f k8s/base/web-service.yaml
kubectl apply -f k8s/base/web-deployment.yaml
# cache/full: kubectl apply -f k8s/overlays/cache/redis-{pvc,service,deployment}.yaml
# search/full: kubectl apply -f k8s/overlays/search/meilisearch-{pvc,service,deployment}.yaml

kubectl -n software-arch-team4 get pods,svc,pvc,cm,secret
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 wait --for=condition=available deployment/web --timeout=120s
# redis/meilisearch too when present:
kubectl -n software-arch-team4 wait --for=condition=available deployment/redis --timeout=120s # cache/full
kubectl -n software-arch-team4 wait --for=condition=available deployment/meilisearch --timeout=120s # search/full

# Seed (reindexes Meilisearch + clears cache automatically when enabled)
kubectl -n software-arch-team4 exec deploy/web -- bin/rails db:seed
```

## 5. Verification (required by assignment)

### a) Application reachable through Service

```bash
kubectl -n software-arch-team4 port-forward svc/web 3000:80 &
sleep 5
curl -i http://localhost:3000/up          # expect HTTP/1.1 200
curl -s http://localhost:3000/ | head -n 20
# Rancher: import cluster (Rancher UI -> Import Existing -> apply cattle URL), then Workloads -> web -> Service web
```

### b) Pod recreated automatically after delete

```bash
kubectl -n software-arch-team4 get pod -l app=web
kubectl -n software-arch-team4 delete pod -l app=web
kubectl -n software-arch-team4 get pods -w  # observe new pod Running, same Deployment
kubectl -n software-arch-team4 port-forward svc/web 3000:80 &
curl -i http://localhost:3000/up  # still 200 after recreation
```

### c) Database data survives pod restart (PVC)

```bash
# Seed if empty
kubectl -n software-arch-team4 exec deploy/web -- bin/rails db:seed
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").books.countDocuments()'

# Insert persistence marker
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.insertOne({check:"before-restart", ts: new Date()})'
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.findOne({check:"before-restart"})'

# Delete mongodb pod (PVC retains /data/db)
kubectl -n software-arch-team4 delete pod -l app=mongodb
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 get pvc mongodb-data  # Bound, not deleted

# Verify data still exists
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.findOne({check:"before-restart"})'
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").books.countDocuments()'
```

## 6. Cleanup

```bash
bin/k8s-down [base|cache|search|full]   # match the overlay you started (default base)
# or kubectl delete -k k8s/overlays/<overlay>
k3d cluster delete dev
# Data is deleted with PVC. To keep data: kubectl delete deployment/mongodb --cascade=orphan
```

## Bugs found & fixed during real deployment

Bugs that only surfaced when running the app in Kubernetes (not caught by `docker compose` or local dev):

1. **Redis cache never used** — `hello_world`/`books` always used in-process `MemoryStore`, so the `cache`/`full` overlays silently didn't cache. Root cause: `config/boot.rb` runs `initialize_cache (bootstrap.rb)` *before* `load_config_initializers`, memoizing `Rails.cache` as `ActiveSupport::Cache::MemoryStore` before `config/initializers/cache_store.rb` ran. Fix in `cache_store.rb`: after setting `config.cache_store`, also reassign `Rails.cache = ...` so RedisCacheStore is actually used.
2. **`meilisearch-rails` DSL errors in `app/models/book.rb`** (raised on boot, `CrashLoopBackOff`):
   - `per_environment: true` is only valid in the global settings hash, not inside a model's `meilisearch do ... end` block → `BadConfiguration`. Moved to `config/initializers/meilisearch.rb`.
   - `attribute :title, :summary, ...` with a block → `"Cannot pass multiple attribute names if block given"`. Split into separate `attribute` calls (block only on the new `author_name` virtual attribute).
   - `primary_key: :id` → `NoMethodError: undefined method 'primary_key' for class Book` (Mongoid has no such method). Removed; the gem falls back to `_id` after we excluded `_id` from the attribute list.
3. **MongoDB `CrashLoopBackOff`** — liveness/readiness probes used `mongosh --eval` with the default 1s probe timeout, which always failed. Fixed in `k8s/base/mongodb-deployment.yaml` with `timeoutSeconds: 10` and `failureThreshold: 3`.
4. **`bin/k8s-up base` error** — `KUSTOMIZE_DIR=k8s/overlays/base` doesn't exist (base lives at `k8s/base/`). Both scripts now special-case `base` → `k8s/base/`.
5. **kustomize deprecation warnings** (v5.7.1) — `patchesStrategicMerge` → `patches: [{path: ...}]` and `commonLabels` → `labels: [{pairs: {...}, includeSelectors: false}]` in all `kustomization.yaml`.
6. **Meilisearch `OOMKilled` while seeding** — indexing the 300-book dataset exceeded the manifest's `memory: 512Mi` limit (k3d node had ~7.8Gi free; pod was killed by cgroup, not the node). Raised limits to `cpu: 1000m` / `memory: 1Gi` in `k8s/overlays/{search,full}/meilisearch-deployment.yaml`. Without this, `db:seed`'s automatic reindex fails with `CrashLoopBackOff`.
7. **Cluster DNS flaky for external names** — CoreDNS forwards external queries to the host resolver (`/etc/resolv.conf`, Docker Desktop `192.168.65.254`), which intermittently times out → `Socket::ResolutionError: Temporary failure in name resolution` even though routing works. Fix (cluster-level, not committed): patch the `kube-system/coredns` ConfigMap `forward .` to `1.1.1.1 8.8.8.8 /etc/resolv.conf` and reload the pod. Add a short retry around `kubectl exec ... db:seed` if you hit this.
8. **Web pod ignores Redis if it boots before Redis is ready** — the `cache_store.rb` initializer `redis.ping` fails at boot when `redis` isn't available yet, silently falling back to `:memory_store`. Symptom: `Rails.cache` is `RedisCacheStore` in a fresh `bin/rails runner` but the puma process never writes keys, and cold/warm request times are identical. Fix: `kubectl -n software-arch-team4 rollout restart deployment/web` after redis is healthy (or rely on `bin/k8s-up`, which waits for deployments between applies).
9. **Docker Compose Meilisearch healthcheck IPv6 bug** — the search/full compose `healthcheck` used `http://localhost:7700/health`, but `wget` resolves `localhost` to `[::1]` first while Meilisearch only listens on IPv4 → `dependency failed to start: container ... is unhealthy`. Fixed to `http://127.0.0.1:7700/health` in `docker-compose.search.yml` and `docker-compose.full.yml`.

## Rancher Integration

Rancher is an optional management UI for the `k3d` cluster and is **not** started by `bin/k8s-up`. The repository does not include Rancher manifests. To use Rancher, start it manually and import the existing cluster.

Rancher provides a graphical interface for the Kubernetes cluster. The workflow is:

1. Start Rancher (once, if not already running): `docker run -d --privileged --restart=unless-stopped -p 443:443 --name rancher rancher/rancher` then open `https://localhost:443`
2. Create/import the cluster: `k3d cluster create dev` (already done by `bin/k8s-up`) creates the K3s cluster. Retrieve the kubeconfig with `k3d kubeconfig get dev`, then in the Rancher UI select *Add Cluster → Import Existing* and apply the generated `kubectl apply -f <cattle-agent-url>` command against that kubeconfig.
3. The `software-arch-team4` namespace, including Deployments (`web`, `mongodb`), Services, PVCs and logs, becomes visible in Rancher. The same objects are available via `kubectl`. All manifests in `k8s/` are standard Kubernetes and remain independent of Rancher.

### 7. Stopping Rancher

Rancher runs as a standalone Docker container (`rancher/rancher`) and is not removed by `bin/k8s-down` or `k3d cluster delete`. It continues running in the background on `https://localhost:443`.

```bash
# Check if Rancher is running (shows name like "rancher" or auto-generated "competent_aryabhata")
docker ps --filter ancestor=rancher/rancher

# Stop and remove (works for any name, 1-2 commands)
docker rm -f $(docker ps -q --filter ancestor=rancher/rancher)
# Or by explicit name (replace with the name from docker ps):
# docker stop rancher && docker rm rancher
# docker stop competent_aryabhata && docker rm competent_aryabhata
```

## Notes

- No modification to `Dockerfile*`, `docker-compose.yml`, `config/mongoid.yml`. Separation via `k8s/` only.
- DRY: ConfigMap centralizes `MONGODB_URI`; both app and future jobs reference it. Secret centralizes credentials. Overlays add `redis`/`meilisearch` services and patch the web Deployment env via `patches` (kustomize `patches: [{path: web-patch.yaml}]`) — the base stays untouched.
- 4 variants mirror the 4 Docker Compose files: `base` ↔ `docker-compose.yml`, `cache` ↔ `docker-compose.cache.yml`, `search` ↔ `docker-compose.search.yml`, `full` ↔ `docker-compose.full.yml`.
- Production variant: change ConfigMap `RAILS_ENV=production PORT=80` and web Deployment `containerPort: 80`, probes port 80, and build from `Dockerfile.production`.
- k3d StorageClass is `local-path` (Rancher provisioner `rancher.io/local-path`), not `standard`.
