# nix-store-operator

A DaemonSet that lazily populates `/nix/store` on Kubernetes nodes from a binary cache. App pods mount the shared store and run nix-built binaries directly — no fat container images required beyond a minimal runner.

## How it works

1. You build your app with nix and export its store paths via a flake output
2. An openkrill module (or any manifest pipeline) creates a ConfigMap labeled `nix-store-operator.ghcr.io/mount=true` containing those paths
3. The store daemon watches for these ConfigMaps and fetches any missing store paths from the binary cache using `nix copy`
4. Your app pod mounts `/var/lib/nixfs/store` as `/nix/store` read-only and runs the binary from a `busybox` container

## Install

```bash
helm repo add nix-store-operator https://general-intelligence-systems.github.io/nix-store-operator
helm repo update
helm install store-daemon nix-store-operator/store-daemon
```

## Flake lib

This flake exports `lib.mkStorePaths` — a helper that computes the full set of `/nix/store` paths a derivation needs (its transitive dependency closure).

### In your app's flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-store-operator.url = "github:general-intelligence-systems/nix-store-operator";
  };

  outputs = { self, nixpkgs, nix-store-operator, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkStorePaths = nix-store-operator.lib.mkStorePaths { inherit pkgs; };
    in {
      packages.${system} = {
        default = <your-app>;
        store-paths = mkStorePaths self.packages.${system}.default;
      };
    };
}
```

The `store-paths` output is a path to a file containing every `/nix/store/...` path the app needs, one per line.

### In your infrastructure repo

Import the app flake and wire it into the openkrill nix-store-operator module:

```nix
openkrill.apps.nix-store-operator = {
  enable = true;
  config-maps.my-app.store-paths = inputs.my-app.packages.x86_64-linux.store-paths;
};
```

The module generates a ConfigMap with the label `nix-store-operator.ghcr.io/mount=true` and embeds the store paths as data. The daemon picks it up and fetches any missing paths.

### App deployment

Your app pod just needs a minimal image and the `/nix/store` volume mount:

```yaml
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
```

## Rolling updates

Version the ConfigMap name by store path hash. Both old and new store paths coexist in the shared store during rollout. Delete the old ConfigMap after the rollout completes.

## Garbage collection

Store paths not referenced by any ConfigMap can be safely removed. The daemon doesn't GC automatically — run this manually or on a schedule:

```bash
comm -23 \
  <(ls /var/lib/nixfs/store | sort) \
  <(kubectl get cm -A -l nix-store-operator.ghcr.io/mount=true -o jsonpath='{.items[*].data.paths}' | tr ' ' '\n' | xargs -I{} basename {} | sort -u) \
  | xargs -I{} rm -rf /var/lib/nixfs/store/{}
```
