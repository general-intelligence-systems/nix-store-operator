#!/usr/bin/env bash
set -euo pipefail

# Usage: ./deploy.sh <name> <flake-ref>
# Example: ./deploy.sh tradeportal .#packages.x86_64-linux.server

NAME=$1
FLAKE=$2

store_path=$(nix build "$FLAKE" --no-link --print-out-paths)
hash=$(basename "$store_path" | cut -c1-8)

nix path-info -r "$store_path" > /tmp/closure.txt

kubectl create configmap "${NAME}-${hash}" \
  --from-file=paths=/tmp/closure.txt \
  --dry-run=client -o yaml | \
  kubectl label --local -f - \
    nix.cia.net/closure=true \
    -o yaml | kubectl apply -f -

echo "ConfigMap ${NAME}-${hash} created"
echo "Store path: ${store_path}"
echo "Mount /var/lib/nixfs/store as /nix/store in your pod"
