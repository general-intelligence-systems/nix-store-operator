{
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
        containers = [
          # ── fuse-daemon sidecar ──────────────────────────────────
          # Mounts FUSE on the shared volume. The real /nix/store in
          # this container has the opencode derivation (baked into
          # the image) and nix for fetching cached deps on demand.
          {
            name = "fuse-daemon";
            image = "opencode-fuse-daemon:latest";
            securityContext.privileged = true;
            volumeMounts = [{
              name = "nix";
              mountPath = "/mnt/nix";
              mountPropagation = "Bidirectional";
            }];
            command = [ "ruby" "/bin/fuse-daemon"
              "--root"      "/data/store"
              "--mount"     "/mnt/nix/store"
              "--whitelist" "/etc/nix/store-whitelist"
            ];
            readinessProbe = {
              exec.command = [ "test" "-d" "/mnt/nix/store" ];
              initialDelaySeconds = 2;
              periodSeconds = 5;
            };
          }

          # ── opencode app ────────────────────────────────────────
          # Mounts the shared volume at /nix. All /nix/store accesses
          # go through the FUSE mount served by the sidecar.
          {
            name = "opencode";
            image = "busybox:latest";
            command = [ "/nix/store/*-opencode-*/bin/opencode" "serve"
              "--hostname" "0.0.0.0"
              "--port" "4096"
            ];
            ports = [{
              name = "http";
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
            livenessProbe = {
              httpGet = { path = "/global/health"; port = "http"; };
              initialDelaySeconds = 10;
              periodSeconds = 30;
              timeoutSeconds = 5;
              failureThreshold = 3;
            };
            readinessProbe = {
              httpGet = { path = "/global/health"; port = "http"; };
              initialDelaySeconds = 5;
              periodSeconds = 10;
              timeoutSeconds = 3;
              failureThreshold = 2;
            };
            startupProbe = {
              httpGet = { path = "/global/health"; port = "http"; };
              initialDelaySeconds = 3;
              periodSeconds = 5;
              failureThreshold = 12;
            };
            resources = {
              requests = { cpu = "100m"; memory = "256Mi"; };
              limits = { cpu = "1"; memory = "1Gi"; };
            };
            volumeMounts = [
              {
                name = "nix";
                mountPath = "/nix";
                mountPropagation = "HostToContainer";
                readOnly = true;
              }
              { name = "home"; mountPath = "/home/opencode"; }
            ];
          }
        ];
        volumes = [
          { name = "nix"; emptyDir = {}; }
          { name = "home"; emptyDir = {}; }
        ];
      };
    };
  };
}
