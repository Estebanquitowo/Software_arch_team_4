# Kubernetes — k3d

The standard manifests in `k8s/` run Rails and MongoDB as independent Kubernetes workloads.

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
k3d cluster create dev  # skip if it already exists
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
bin/k8s-down              # stops workloads but preserves the PVC and Secret
k3d cluster delete dev
# Data is deleted with PVC. To keep data: kubectl delete deployment/mongodb --cascade=orphan
```

## 7. Rancher Manager (optional)

This project uses **Rancher Manager**, not Rancher Desktop. Rancher Manager runs separately as an administration UI for the already-created `k3d-dev` cluster; it does not replace the Kubernetes manifests.

```bash
# From repository root
bin/rancher-up
# Open https://localhost:8443 and finish the initial setup.
# In the UI choose Import Existing, copy the generated registration URL, then:
bin/rancher-import <registration-url-from-rancher>
```

The import action applies Rancher's generated registration manifest explicitly to context `k3d-dev`. Once the Rancher agent connects, the UI exposes the cluster's nodes and the `software-arch-team4` workloads, Services, PVC, ConfigMap and Secret.

## Notes

- DRY: ConfigMap centralizes `MONGODB_URI`; both app and future jobs reference it. Secret centralizes credentials.
- Production variant: change ConfigMap `RAILS_ENV=production PORT=80` and web Deployment `containerPort: 80`, probes port 80, and build from `Dockerfile.production`.
- k3d StorageClass is `local-path`, not `standard`.
