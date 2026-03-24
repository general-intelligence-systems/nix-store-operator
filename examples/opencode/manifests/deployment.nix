{ lib, image, ocBin, apiImage ? "opencode-api:latest" }:

let
  sidecar = lib.mkSidecar { inherit image; };
  nixVol  = lib.mkNixVolume;
in {
  apiVersion = "apps/v1";
  kind = "Deployment";
  metadata = {
    name = "opencode-server";
    namespace = "opencode";
    labels.app = "opencode-server";
  };
  spec = {
    replicas = 1;
    selector.matchLabels.app = "opencode-server";
    template = {
      metadata.labels.app = "opencode-server";
      spec = {
        # Native sidecar (k8s >= 1.28): starts before containers, runs for pod lifetime
        initContainers = [ sidecar ];

        containers = [
          # ── opencode server ─────────────────────────────────────
          {
            name = "opencode";
            image = "busybox:latest";
            command = [ "/bin/sh" "-c" ''
              echo "waiting for nix store..."
              while ! ls /nix/store/${ocBin}/bin/opencode 2>/dev/null; do sleep 1; done
              exec /nix/store/${ocBin}/bin/opencode serve --hostname 0.0.0.0 --port 4096
            '' ];
            ports = [{
              name = "opencode";
              containerPort = 4096;
              protocol = "TCP";
            }];
            env = [
              { name = "HOME"; value = "/home/opencode"; }
              {
                name = "OPENCODE_SERVER_PASSWORD";
                valueFrom.secretKeyRef = {
                  name = "opencode-server-auth";
                  key = "password";
                  optional = true;
                };
              }
            ];
            startupProbe = {
              httpGet = { path = "/doc"; port = "opencode"; };
              initialDelaySeconds = 5;
              periodSeconds = 5;
              failureThreshold = 60;
            };
            readinessProbe = {
              httpGet = { path = "/doc"; port = "opencode"; };
              periodSeconds = 10;
            };
            livenessProbe = {
              httpGet = { path = "/doc"; port = "opencode"; };
              periodSeconds = 30;
            };
            resources = {
              requests = { cpu = "100m"; memory = "256Mi"; };
              limits = { cpu = "1"; memory = "1Gi"; };
            };
            volumeMounts = [
              nixVol.mount
              { name = "home"; mountPath = "/home/opencode"; }
            ];
          }

          # ── API wrapper ─────────────────────────────────────────
          # Bun HTTP server using @opencode-ai/sdk. Exposes preset
          # prompts and a custom prompt endpoint.
          {
            name = "api";
            inherit apiImage;
            image = apiImage;
            ports = [{
              name = "api";
              containerPort = 3000;
              protocol = "TCP";
            }];
            env = [
              { name = "OPENCODE_URL"; value = "http://localhost:4096"; }
              { name = "PORT"; value = "3000"; }
            ];
            readinessProbe = {
              httpGet = { path = "/health"; port = "api"; };
              initialDelaySeconds = 10;
              periodSeconds = 10;
            };
            livenessProbe = {
              httpGet = { path = "/health"; port = "api"; };
              periodSeconds = 30;
            };
          }
        ];

        volumes = [
          nixVol.volume
          { name = "home"; emptyDir = {}; }
        ];
      };
    };
  };
}
