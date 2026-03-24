# OpenCode Server — fuse-daemon example

Deploys [OpenCode](https://opencode.ai) as a headless HTTP server on Kubernetes using fuse-daemon — a Ruby FUSE daemon that lazily fetches `/nix/store` paths from a binary cache.

The Docker image contains only the opencode derivation (non-cached) and a whitelist of its full closure. All standard nixpkgs dependencies (glibc, openssl, etc.) are fetched on demand by the FUSE daemon via `nix copy` when the binary first accesses them.

## Build the image

```bash
docker build -t opencode-fuse-daemon:latest .
```

The Dockerfile:
1. Installs nix, ruby, and the rfuse gem
2. Builds the opencode derivation from the flake
3. Generates the whitelist (`nix-store -qR`) -- the full closure
4. Garbage collects everything except the opencode output path
5. Bakes `fuse-daemon.rb`, the whitelist, and the opencode binary into the image

## Deploy

```bash
nix build .#manifests
kubectl apply -f result/
```

## Architecture

```
Pod
├── fuse-daemon sidecar (privileged, /dev/fuse)
│   ├── image: opencode-fuse-daemon (has nix, ruby, rfuse, opencode drv, whitelist)
│   ├── real /nix/store has the opencode binary (from image)
│   ├── mounts FUSE at /mnt/nix/store on shared emptyDir volume
│   ├── on access to whitelisted missing path → nix copy from cache
│   └── on access to non-whitelisted path → ENOENT
│
└── opencode app (busybox)
    ├── mounts shared volume at /nix (HostToContainer propagation)
    ├── sees /nix/store via FUSE
    └── runs: /nix/store/<hash>-opencode/bin/opencode serve
        → dynamic linker loads /nix/store/<hash>-glibc/lib/libc.so.6
        → FUSE intercepts → nix copy → served
```

## Health checks

| Probe | Path | Interval | Purpose |
|-------|------|----------|---------|
| **Startup** | `GET /global/health` | every 5s, up to 60s | Waits for opencode to start |
| **Readiness** | `GET /global/health` | every 10s | Gates Service traffic |
| **Liveness** | `GET /global/health` | every 30s | Restarts if unresponsive |

## Access the server

```bash
kubectl port-forward -n opencode svc/opencode-server 4096:4096
curl http://localhost:4096/global/health
```

## File layout

```
examples/opencode/
├── Dockerfile             # Builds the fuse-daemon + opencode image
├── flake.nix              # Outputs Kubernetes manifests as JSON
├── manifests/
│   ├── namespace.nix
│   ├── deployment.nix     # fuse-daemon sidecar + opencode app + shared volume
│   ├── service.nix
│   └── secret.nix
└── README.md
```

The FUSE daemon itself lives at the repo root: [`fuse-daemon.rb`](../../fuse-daemon.rb)
