# Kubernetes — k3d + Rancher (k3d-only)

Isolated manifests in `k8s/` — does not modify `Dockerfile*`, `docker-compose.yml`, or app code. The manifests are standard Kubernetes resources. Rancher is an optional UI that imports the existing `k3d` cluster — see `## Rancher Integration` after Cleanup.

## Quick start — 1 command

```bash
# From repository root, like docker compose up --build:
bin/k8s-up
```

View the application (requires an extra terminal — `ClusterIP` is internal):

```bash
# Keep this running in a separate terminal:
kubectl -n software-arch-team4 port-forward svc/web 3000:80
# Then open http://localhost:3000 or: curl -i http://localhost:3000/up  # expect 200
# To stop the redirection, press Ctrl+C in the port-forward terminal (or kill %1 if run with &)
```

`bin/k8s-up` does: `docker build -f Dockerfile.dev -t software_arch_team_4:k8s .` → `k3d cluster create dev` (if missing) → `k3d image import` → create `app-secret` → `kubectl apply -k k8s/` → wait for ready.

Stop: `bin/k8s-down` (or `k3d cluster delete dev`).

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

`k8s/secret.yaml` is a **template** excluded from `kustomization.yaml` to avoid overwriting real secrets.

```bash
kubectl apply -f k8s/namespace.yaml

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
# kubectl apply -f k8s/secret.yaml
```

## 4. Deploy (after secret exists)

```bash
# Option A: kustomize (secret excluded - create it first as in step 3)
kubectl apply -k k8s/

# Option B: explicit ordered apply (avoids race)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
# secret already created in step 3
kubectl apply -f k8s/mongodb-pvc.yaml
kubectl apply -f k8s/mongodb-service.yaml
kubectl apply -f k8s/mongodb-deployment.yaml
kubectl apply -f k8s/web-service.yaml
kubectl apply -f k8s/web-deployment.yaml

kubectl -n software-arch-team4 get pods,svc,pvc,cm,secret
kubectl -n software-arch-team4 wait --for=condition=available deployment/mongodb --timeout=120s
kubectl -n software-arch-team4 wait --for=condition=available deployment/web --timeout=120s
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
bin/k8s-down              # or kubectl delete -k k8s/
k3d cluster delete dev
# Data is deleted with PVC. To keep data: kubectl delete deployment/mongodb --cascade=orphan
```

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
- DRY: ConfigMap centralizes `MONGODB_URI`; both app and future jobs reference it. Secret centralizes credentials.
- Production variant: change ConfigMap `RAILS_ENV=production PORT=80` and web Deployment `containerPort: 80`, probes port 80, and build from `Dockerfile.production`.
- k3d StorageClass is `local-path` (Rancher provisioner `rancher.io/local-path`), not `standard`.
