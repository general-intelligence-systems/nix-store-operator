# nix-store-operator

A DaemonSet that lazily populates `/nix/store` on Kubernetes nodes from a binary cache. App pods mount the shared store and run nix-built binaries directly — no fat container images required beyond a minimal runner.

## How it works

1. You build your app with nix and generate its store paths (the full list of `/nix/store` paths it needs)
2. You create a ConfigMap with that store paths list, labeled `nix-store-operator.ghcr.io/mount=true`
3. The store daemon watches for these ConfigMaps and fetches any missing store paths from the binary cache using `nix copy`
4. Your app pod mounts `/var/lib/nixfs/store` as `/nix/store` read-only and runs the binary

## Install

```bash
helm install store-daemon ./charts/store-daemon
```

## Deploy an app

```bash
# Build and get store paths
nix build .#myapp --print-out-paths
nix path-info -r .#myapp > store-paths.txt

# Create store paths ConfigMap
kubectl create configmap myapp \
  --from-file=paths=store-paths.txt \
  -l nix-store-operator.ghcr.io/mount=true

# Deploy (mount the shared store)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: app
          image: busybox:latest
          command: ["/nix/store/...-myapp/bin/myapp"]
          volumeMounts:
            - name: nix-store
              mountPath: /nix/store
              readOnly: true
      volumes:
        - name: nix-store
          hostPath:
            path: /var/lib/nixfs/store
            type: DirectoryOrCreate
EOF
```

Or use the helper:

```bash
./deploy.sh myapp .#packages.x86_64-linux.server
```

## Rolling updates

Version the ConfigMap name by store path hash. Both old and new store paths coexist in the shared store during rollout. Delete the old ConfigMap after the rollout completes.

```bash
./deploy.sh myapp .#myapp   # creates myapp-abc123
# later...
./deploy.sh myapp .#myapp   # creates myapp-def456, old paths stay
kubectl delete configmap myapp-abc123  # cleanup after rollout
```

## Garbage collection

Store paths not referenced by any ConfigMap can be safely removed. The daemon doesn't GC automatically — run this manually or on a schedule:

```bash
comm -23 \
  <(ls /var/lib/nixfs/store | sort) \
  <(kubectl get cm -A -l nix-store-operator.ghcr.io/mount=true -o jsonpath='{.items[*].data.paths}' | tr ' ' '\n' | xargs -I{} basename {} | sort -u) \
  | xargs -I{} rm -rf /var/lib/nixfs/store/{}
```
