# Base image is the fuse-daemon published by the nix-store-operator CI.
# It contains: ruby, rfuse, nix-download, fuse-daemon.rb
FROM ghcr.io/general-intelligence-systems/nix-store-operator:latest

# These are produced by the flake:
#
#   nix build .#whitelist   -> result is the store-whitelist file
#   nix build .#app-store   -> result/ contains non-cached store paths
#
# Then build the image:
#
#   docker build \
#     --build-context whitelist=$(nix build .#whitelist --no-link --print-out-paths) \
#     --build-context app-store=$(nix build .#app-store --no-link --print-out-paths) \
#     -t opencode-fuse-daemon:latest .
#
COPY --from=whitelist / /etc/nix/store-whitelist
COPY --from=app-store / /data/store/
