# Rails replicas (Assignment 4, without the edge proxy)

`base/web-deployment.yaml` now requests three replicas. All overlays inherit
that setting. The existing `web` ClusterIP Service selects their `app: web`
label and forwards port 80 to 3000; there is no Service per replica and no
session affinity requirement. MongoDB, Redis and Meilisearch remain shared
services, not one instance of each per Rails Pod.

## Statelessness and shared images

- Rails uses its default `ActionDispatch::Session::CookieStore`. Each replica
  must use the same `app-secret` / `SECRET_KEY_BASE`, cookie key and application
  configuration. Do not rotate the secret per Pod. The current Deployment's
  `envFrom` already injects the same ConfigMap and Secret into every replica.
- `ImageStorage` already supports `IMAGE_STORAGE_PATH`; no upload/model/UI
  changes are needed. The ConfigMap sets `/data/images`, mounted from the same
  `images-data` PVC in every Rails Pod. MongoDB stores the relative references.
- The PVC requests 1 Gi using the default StorageClass. On the local **single-
  node k3d** cluster this is `local-path` / `ReadWriteOnce`. RWO permits multiple
  Pods on the **same node**, not shared writes across different nodes. PV node
  affinity keeps consumers on that node. This demonstrates horizontal Rails
  replication, not resilience to losing the node/cluster. Multi-node placement
  needs an RWX-capable shared filesystem or another shared storage backend;
  merely changing the access-mode string does not provide that backend.
- `.dockerignore` excludes local uploads so application images never bake in
  user files. Before upgrading an existing image-enabled deployment, preserve
  any files currently in its container filesystem and copy them to the PVC
  without overwriting existing files. The cluster audited for this change had
  no existing image references or upload files to migrate.
- Cache data is shared in Redis; `CacheGeneration` and `SearchSyncState` are
  persisted in MongoDB. Redis outages do not select a process-local MemoryStore.
  Logs, PIDs, request upload tempfiles and code caches are disposable local
  state, unlike the final uploaded images. No application jobs/channels were
  found that require shared in-process state.

## Deploy and check without seeds

Use the intended context explicitly. With the existing namespace/`app-secret`
and selectors matching the repository, build/import/apply the full overlay:

```sh
docker build -f Dockerfile.dev -t software_arch_team_4:k8s .
k3d image import software_arch_team_4:k8s -c dev
kubectl --context k3d-dev apply -k k8s/overlays/full
kubectl --context k3d-dev -n software-arch-team4 rollout status deployment/web --timeout=180s
kubectl --context k3d-dev -n software-arch-team4 get deploy,pods,svc,pvc
kubectl --context k3d-dev -n software-arch-team4 get endpointslices -l kubernetes.io/service-name=web
```

When reusing the same image tag for a later code-only deployment, import it and
explicitly roll out new Pods; applying unchanged Pod templates does not restart
them. This change modifies the Pod template (shared mount), so it triggers a
rollout. `bin/k8s-up` runs seeds by default: do not use it for a preservation-only
upgrade without `K8S_SKIP_SEED=1`. No seeds are necessary to scale existing data.

### Compatibility with an older cluster

The tested cluster still had the additional immutable selector
`app.kubernetes.io/part-of: software-arch-team4` on its old Deployments. A direct
apply of the newer base tries to remove it and fails. Inspect existing selectors
first; do **not** delete Deployments/PVCs to bypass this error.

For that specific old cluster, the verification used a temporary Kustomize
wrapper equivalent to the following file at `tmp/k8s-scaling-legacy/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../k8s/overlays/full
labels:
  - pairs:
      app.kubernetes.io/part-of: software-arch-team4
    includeSelectors: true
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: mongodb
        namespace: software-arch-team4
      $patch: delete
```

Apply that wrapper instead of `full` **only to this existing legacy deployment**.
The patch omits MongoDB's Deployment from the generated apply payload; with
ordinary `kubectl apply` and **no pruning** it does not delete the live Deployment.
Thus MongoDB's Pod, data and settings stay untouched. This is not a fresh-cluster
overlay: it assumes MongoDB already exists. Repository selectors remain unchanged
so newer clusters are not broken to accommodate this older one.

## Verification and boundaries

- `kubectl port-forward svc/web 3000:80` allows browser access but selects one
  Pod: it does **not** prove Service traffic distribution. Probe `http://web`
  from inside the namespace with fresh TCP connections, a unique query marker
  and `Host: localhost`, then correlate only that marker in `kubectl logs -l
  app=web --prefix`. The smoke test used 18 sequential requests, not a load test.
- Check all three ready EndpointSlice addresses and identical image IDs.
- Check cookie portability with a real form/CSRF token from Pod A, POST to B,
  and flash/redirect on C; no test-only application endpoint is necessary.
- Upload a uniquely identified test author/book image through normal HTTP and
  compare image bytes from each Pod, including the replacement Pod after deletion.
  Remove only those explicitly owned test records/assets afterwards.
- Delete one **named Rails Pod**, never the Deployment/PVC; verify other Pods
  keep serving and the Deployment returns to 3/3. This does not promise survival
  of an HTTP request already in flight on a process killed abruptly.
- Do not use `bin/k8s-down` as a pause: it deletes manifests including PVCs and
  the namespace. A surviving PVC protects against Pod replacement, not deletion
  of the volume or the local cluster. MongoDB still has a single replica.

No HAProxy, TLS, domain, edge asset policy or proxy integration is configured by
this change. The future integration target remains the existing `web:80`
Service. `SERVE_STATIC` remains at its existing default; no edge policy is assumed.

Focused manifest/session-contract tests are in
`test/deployment/kubernetes_scaling_test.rb`; existing upload/cache/search tests
remain unchanged. Run all tests in the isolated regression stack:

```sh
docker compose -p a3-regression -f test/compose.yml run --rm tests sh /source/test/support/run-suite.sh --seed 12345
```
