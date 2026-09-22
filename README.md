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

  Like Docker Compose, Kubernetes provides **4 variants** via kustomize base + overlays (`bin/k8s-up [base|cache|search|full]`) to enable optional Redis caching and Meilisearch search. HAProxy for Kubernetes is planned for the edge (Phase 16) and not yet included.

### Reverse Proxy (HAProxy)

`haproxy/` is an isolated module (no app code changes). It provides:

* **Edge entrypoint:** `haproxy:3.0-alpine` with `frontend http_front` binding `*:80` and `*:443 ssl crt /usr/local/etc/haproxy/certs/self-signed.pem`. TLS is terminated at the proxy, `web` speaks plain HTTP (`3000`).
* **Custom domain:** ACL `host_app hdr(host) -i app.localhost localhost` — app is served under `app.localhost` (`*.localhost` resolves to `127.0.0.1` via systemd-resolved). Requests with other `Host` are `403`.
* **Static at edge:** `image_data:/data/images:ro` mounted to HAProxy, `acl is_images/is_assets` + `cache static_cache` (`total-max-size 128`, `max-object-size 10M`, `max-age 86400`). First fetch goes to `web` (`ImagesController` via shared volume), HAProxy stores (`http-response cache-store`) and serves `Cache-Control: public, max-age=86400` on hits (`<CACHE>` in logs, `Age` header). `SERVE_STATIC=false` when proxy is present (fallback `true` without proxy).
* **Load balancing:** `docker-compose.scale.yml` runs `web` with `deploy: replicas: 3` (Compose v2, no Swarm) + `resolvers docker (127.0.0.11:53)` + `server-template web 3 web:3000 resolvers docker ... check` `balance roundrobin`. Explicit `web1/web2/web3` fallback is documented in `haproxy.scale.cfg`. Health checks are `GET /up` with `Host: localhost`.
* **Certs:** `haproxy/certs/self-signed.pem` (crt+key) generated for `app.localhost`. See *HTTPS* below.

## Local Development and Deployment 

### Option A: Docker Compose (6 variants — app works with or without cache/search/proxy/scale)

The app implements **optional** components via Strategy pattern:

* **Cache:** `Redis` (`redis:7-alpine`) with `Rails.cache = :redis_cache_store`. If `REDIS_URL` unreachable/missing → gracefully falls back to `:memory_store` (`CacheService.fetch` rescues and yields directly, so requests never 500).
* **Search:** `Meilisearch` (`getmeili/meilisearch:v1.12`) with `meilisearch-rails`. If `MEILISEARCH_URL` unreachable/missing → gracefully falls back to native MongoDB regex/`$text` search (`SearchService`).
* **Uploads:** book covers and author images are stored under `IMAGE_STORAGE_PATH` (default `/data/images`; the compose files mount a shared `image_data` volume there) and served at `/images/<relative>` by `ImagesController`. In multi-instance deployments all instances must share this storage path.
* **Static assets:** the app serves `public/` files and `/images/*` uploads by default (`SERVE_STATIC=true`). When a reverse proxy is present, `SERVE_STATIC=false` — app stops serving via `public_file_server` and `ImagesController` fallback, HAProxy owns `/images/*`/`/assets/*` at the edge with shared `image_data:ro` and `static_cache`.
* **Proxy:** `haproxy:3.0-alpine` terminates TLS, enforces `app.localhost` ACL, and proxies to `web:3000` with health `GET /up`. See `haproxy/haproxy.cfg` (single) and `haproxy/haproxy.scale.cfg` (3× via `resolvers docker` + `server-template`).
* **Hosts:** Rails `config.hosts` now allows `app.localhost`, `web`, `haproxy`, `*.localhost` for HAProxy health checks and custom domain (see `config/environments/development.rb`).

Compose files:

| File | Services | Env / Ports | Purpose |
|------|----------|-------------|---------|
| `docker-compose.yml` | `web` + `mongodb` | `CACHE_ENABLED=false` `SEARCH_ENABLED=false` `SERVE_STATIC=true` — `web 3000:3000` | **Baseline, no proxy** — backward compat `http://localhost:3000` |
| `docker-compose.cache.yml` | + `redis` | `CACHE_ENABLED=true` `SERVE_STATIC=true` — `3000:3000` | Cache only, no proxy |
| `docker-compose.search.yml` | + `meilisearch` | `SEARCH_ENABLED=true` `SERVE_STATIC=true` — `3000:3000` | Search only, no proxy |
| `docker-compose.proxy.yml` | `web`+`mongodb`+`haproxy` | `SERVE_STATIC=false` — `web expose:3000`, `haproxy 80:80 443:443` | **App+DB+Proxy** (Phase 9) |
| `docker-compose.full.yml` | `web`+`mongodb`+`redis`+`meilisearch`+`haproxy` | `CACHE/SEARCH=true` `SERVE_STATIC=false` — `haproxy 80:80 443:443` | **Full + Proxy** (Phase 10) |
| `docker-compose.scale.yml` | `web×3`+`mongodb`+`redis`+`meilisearch`+`haproxy` | `replicas:3` + `server-template 3` `SERVE_STATIC=false` — `haproxy 80:80 443:443` | **×3 + LB + Cache + Search** (Phase 11) |

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

`haproxy` mounts `haproxy/certs:ro` and `image_data:/data/images:ro`. Rails `SERVE_STATIC=false` when proxy is present, so `public_file_server` is not relied on — edge serves `/images/*`/`/assets/*`.

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
# 5) Uploaded images via shared volume (SERVE_STATIC=false, cache)
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

### Verify Cluster (required by Assignment 2)
```sh
# a) Reachable through Service
kubectl -n software-arch-team4 port-forward svc/web 3000:80 
# In another terminal, do the following command
curl -i http://localhost:3000/up   # should throw 200
```

```sh
# b) Self-healing: pod recreated automatically
kubectl -n software-arch-team4 delete pod -l app=web
kubectl -n software-arch-team4 get pods   # wait for new web pod to be READY
# Repeat "a)" steps:
kubectl -n software-arch-team4 port-forward svc/web 3000:80 
# In another terminal, do the following command
curl -i http://localhost:3000/up   # should throw 200
```

```sh
# c) PVC survives restart
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.insertOne({check:"before-restart"})'
kubectl -n software-arch-team4 delete pod -l app=mongodb
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 exec deploy/mongodb -- mongosh --eval 'db.getSiblingDB("software_arch_team4_development").test_persistence.findOne({check:"before-restart"})' # still exists
```

## Verify Caching & Search (required by Assignment 3)

The target configuration for these correctness tests is the **full** variant (`web` + `mongodb` + `redis` + `meilisearch`). `db:seed` now also **clears the cache** and **reindexes Meilisearch** automatically when those features are enabled.

```sh
# 1) Bring up the full stack (code is volume-mounted, so changes are live)
# full now runs behind HAProxy at 80/443 (web not on :3000):
docker compose -f docker-compose.full.yml up -d --build

# 2) Seed the database (also clears cache + reindexes when available)
docker compose -f docker-compose.full.yml exec web bin/rails db:seed
# for scale with replicas: docker exec software_arch_team_4-web-1 bin/rails db:seed

# 3) Optional: start cold, so the first request below is a real cache miss
docker compose -f docker-compose.full.yml exec web bin/rails cache:clear
```

### a) Reading an item caches/indexes it

Hit every cached endpoint. The first request is a cache **miss**: it reads MongoDB and fills the cache (`CacheService.fetch`). Repeat a request right after `cache:clear` and the second call is served from the cache.

> **Ports:** `docker-compose.full.yml`/`proxy`/`scale` are behind HAProxy — use `http://app.localhost` (or `http://localhost` on `:80`, `https://app.localhost` with `-k`) without `:3000`. Baseline `docker-compose.yml`/`cache`/`search` (no proxy) still use `http://localhost:3000`.

```sh
# via HAProxy edge (full/proxy/scale)
curl -s "http://app.localhost/reports/authors_summary"   >/dev/null
curl -s "http://app.localhost/reports/top_rated_books"   >/dev/null
curl -s "http://app.localhost/reports/top_selling_books" >/dev/null
curl -s "http://app.localhost/books"                     >/dev/null
curl -s "http://app.localhost/search?q=war"              >/dev/null
# or: curl -s "http://localhost/reports/authors_summary" >/dev/null
# baseline without proxy:
# curl -s "http://localhost:3000/reports/authors_summary" >/dev/null
```

Proof the cache was filled (Redis keys now exist):

```sh
docker compose -f docker-compose.full.yml exec redis redis-cli KEYS 'reports/*'
docker compose -f docker-compose.full.yml exec redis redis-cli KEYS 'books/*'
docker compose -f docker-compose.full.yml exec redis redis-cli KEYS 'search/*'
```

Proof books are indexed (Meilisearch document count == `Book.count`):

```sh
curl -s "http://localhost:7700/indexes/books/stats" -H "Authorization: Bearer dev-master-key"
```

### b) Add / edit / delete items through the app

Through the UI at `http://app.localhost` (`https://app.localhost -k` for TLS) or `http://localhost:3000` for baseline:

* Add/edit/delete a **review** — `/books/<id>` → *New Review* (also reachable at `/books/<id>/reviews`).
* Add/edit/delete a **sale** — `/books/<id>` → *New Sale*.
* Edit or delete a **book** — `/books/<id>/edit`.
* Edit an **author** — `/authors/<id>/edit`, then reload `/reports/authors_summary` (sorted by name).

Or script the mutation with `rails runner` (print the book id/title to use below):

```sh
docker compose -f docker-compose.full.yml exec web bin/rails runner '
  b = Book.first
  puts "id=#{b.id} title=#{b.title}"
  b.reviews.create!(rating: 5, title: "QA Test", content: "zephyrx", reviewer_name: "QA")
  puts "avg_score=" + b.reload.avg_score.to_s
'
```

### c) A later read returns the updated value and search reflects the change

**Cache invalidation** — the mutation above triggered `Book#after_save` → `delete_matched("reports/*", "books/*", "search/*")`, so the affected keys are gone immediately:

```sh
docker compose -f docker-compose.full.yml exec redis redis-cli KEYS 'reports/*'   # emptied for that resource
```

**Read returns fresh data** — the search results table shows the recomputed `avg_score`:

```sh
curl -s "http://app.localhost/search?q=zephyrx"        # matched via the indexed review text
curl -s "http://app.localhost/reports/top_rated_books" # recomputed after invalidation
# baseline: curl -s "http://localhost:3000/search?q=zephyrx"
```

**Index is synchronized** — editing the book's summary is searchable right away (`meilisearch synchronous: true`):

```sh
docker compose -f docker-compose.full.yml exec web bin/rails runner '
  b = Book.first
  b.update!(summary: b.summary + " xanthous")
'
curl -s "http://app.localhost/search?q=xanthous"   # returns the book (new summary indexed)
```

**Deleting removes the index entry and the cached value**:

```sh
docker compose -f docker-compose.full.yml exec web bin/rails runner '
  r = Book.first.reviews.find_by(content: "zephyrx"); r.destroy!
'
curl -s "http://app.localhost/search?q=zephyrx"   # no results anymore
docker compose -f docker-compose.full.yml exec redis redis-cli KEYS 'reports/*'   # invalidated again
```

### d) Stale data

* **None expected.** Every mutation invalidates the cache: `Review`/`Sale` callbacks recompute `avg_score`/`number_of_sales` and re-save the book, which fires `Book#after_save` → `CacheService.delete_matched("reports/*", "books/*", "search/*")`. Editing a `Book` or `Author` directly invalidates `reports/*` (author summary). Search synchronization now goes through `SearchSyncService`: failures leave persistent recovery debt and reads use MongoDB until reconciliation succeeds (see below).
* **Accepted / justified cases.** The per-key TTL (5–10 min) is only a safety net, never the invalidation mechanism. If Redis is unreachable at boot the app falls back to `:memory_store` (documented as bug #8 in `k8s/README.md`), and if Meilisearch is down search falls back to MongoDB regex — in both cases the app stays functional and consistent with MongoDB on the next read.

The same tests run on the Kubernetes stack: `bin/k8s-up full`, port-forward `svc/web 3000:80` (service port 80) for the `curl` steps, and use `kubectl -n software-arch-team4 exec deploy/web -- bin/rails runner '<code>'` instead of `docker compose ... exec web`.

## Search failure and recovery

MongoDB remains the source of truth. `SearchSyncService` owns all application
index writes; the gem's automatic indexing/removal callbacks are disabled.
Book callbacks and `BookStatisticsRecalculator` (Review/Sale changes) delegate to
this service using fresh persisted data. Expected Meilisearch failures are logged
without credentials or document payloads and do not turn successful CRUD writes
into HTTP 500. MongoDB and programming errors are not silently swallowed.

`SearchSyncState` stores `dirty`, a monotonic `revision`, and an exclusive
`lock_token`/`locked_at` in MongoDB, scoped to the configured index/server within
the application's database. Missing state starts dirty. Writes advance revision
and mark dirty even with `SEARCH_ENABLED=false`, without contacting Meilisearch.
When clean, normal writes synchronously update/delete the affected document and
verify the remote task succeeded. With previous recovery debt, a successful write
attempts one full reconciliation: settle pending index tasks, clear all documents,
then index the current Books in batches of 100. Every new settings/clear/index
task must finish with `status == succeeded`; HTTP 202 or `await` alone is not proof.
This also removes documents for Books deleted during an outage, including when
MongoDB has no Books left.

Clean publication requires the same revision and lock token. Concurrent writers
that cannot acquire the lock do not wait: their MongoDB changes stay saved and
dirty remains true until a later successful reconciliation. The lock also
serializes incremental index writes with rebuilds. Recovery has a 15-second task
budget, with SDK HTTP timeout of 2 seconds and automatic retries disabled; an
in-flight HTTP call can extend that budget. There is no periodic recovery polling,
startup ping/rebuild, or reconciliation triggered by a search. Task completion
waits are bounded and occur only inside an explicit synchronization attempt.

While dirty, search bypasses its result cache and uses MongoDB. Clean search cache
keys include state identity, epoch and revision, so old/in-flight results cannot
be reused after clean publication. A failed clean-index search marks dirty and
falls back without rebuilding. General cache generation, purge and individual
average-score caching are unchanged.

For first activation or recovery without another write, run the manual task on
the selected search-enabled Compose stack (no seeds required):

```sh
docker compose -f docker-compose.full.yml exec web bin/rails search:reconcile
```

`search:reindex` is an alias for that full reconciliation. `search:clear` uses the
same coordination/task checks but deliberately leaves the state dirty. Tasks
report `disabled` without a network call if search is off; failed/busy/changed-
revision reconciliation exits unsuccessfully so operators must not assume clean.

Locks are released in `ensure`, only by their owner. An abrupt process death can
leave an abandoned lock; **never unlock a live owner**. After stopping/verifying
the old owner, inspect `SearchSyncState.current` in Rails console and use its exact
token with `bin/rails 'search:unlock[TOKEN]'`, setting
`SEARCH_SYNC_OWNER_STOPPED=yes` in that command's environment. This guarded task
keeps dirty and advances revision; run `search:reconcile` afterwards. There is no
automatic expiration or lock stealing.

Limits: the MongoDB document write and dirty marker are separate operations, so a
process crash between them can escape tracking. Raw collection writes, `set`,
`delete_all` and other callback-bypassing operations need explicit reconciliation.
A crash during rebuilding keeps dirty and may require the manual lock procedure.
This is not a distributed transaction. Author rename propagation and search-query
cache-key normalization are separate outstanding issues, not fixed by this block.

Regression checks use disposable MongoDB/Redis/Meilisearch services, random test
databases/indexes and a TCP fault proxy; they do not seed or modify normal data:

```sh
docker compose -p a3-regression -f test/compose.yml run --rm tests sh /source/test/support/run-suite.sh --seed 12345
docker compose -p a3-regression -f test/compose.yml stop
```

The real-engine test checks title/summary/reviews, relevance, pagination, HTTP
writes during network failure, dirty-cache bypass, recovery removing an orphaned
document, review edits/deletes, and the manual clear/reindex/reconcile tasks.

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
