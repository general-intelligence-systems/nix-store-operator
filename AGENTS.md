# Agent Guidelines

## Releasing a New Version

The current version is stored in `.github/release-version`. To release, use `bin/tag-release`:

```bash
bin/tag-release patch   # e.g. 0.1.0 -> 0.1.1
bin/tag-release minor   # e.g. 0.1.0 -> 0.2.0
bin/tag-release major   # e.g. 0.1.0 -> 1.0.0
```

This script:

1. Reads the current version from `.github/release-version`
2. Increments the specified segment (and resets lower segments to 0)
3. Writes the new version back to `.github/release-version`
4. Commits the version bump as `Release vX.Y.Z`
5. Creates a git tag `vX.Y.Z`
6. Pushes the commit and tag to origin

Pushing the tag triggers two GitHub Actions workflows:

- **`build-image.yml`** - Builds the Docker image and pushes it to `ghcr.io/general-intelligence-systems/nix-store-operator` tagged as `latest`, the semver version, and the commit SHA.
- **`build-chart.yml`** - Packages the Helm chart from `charts/` and publishes it to the `gh-pages` branch using `helm/chart-releaser-action`.

Do **not** manually edit `.github/release-version` or create tags by hand. Always use `bin/tag-release`.

## Flake Lib

This repo is a nix flake that exports `lib.mkStorePaths`. This is the helper that consuming app flakes use to compute their store paths.

```nix
mkStorePaths = { pkgs }: drv:
  "${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths";
```

It takes a derivation and returns the path to a file containing its full transitive `/nix/store` dependency list. Consuming flakes expose this as a `packages.<system>.store-paths` output.

The openkrill module (`apps/stable/nix-store-operator`) reads these paths via `builtins.readFile` (IFD) and embeds them in ConfigMaps labeled `nix-store-operator.ghcr.io/mount=true`.

## Architecture

- **Operator** (`store-daemon.rb`) — DaemonSet that watches labeled ConfigMaps and runs `nix copy --from <cache>` to fetch missing store paths onto each node
- **Helm chart** (`charts/store-daemon/`) — deploys the operator; published to gh-pages and will be added to nixhelm
- **Flake lib** (`flake.nix`) — `lib.mkStorePaths` helper for consuming flakes
- **Openkrill module** — lives in the openkrill repo at `apps/stable/nix-store-operator/`, generates ConfigMaps from flake inputs
