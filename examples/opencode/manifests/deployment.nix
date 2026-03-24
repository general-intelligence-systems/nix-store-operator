{ lib, image, ocBin }:

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

        containers = [{
          name = "opencode";
          image = "busybox:latest";
          command = [ "/bin/sh" "-c" ''
            echo "waiting for nix store..."
            while ! ls /nix/store/${ocBin}/bin/opencode 2>/dev/null; do sleep 1; done
            exec /nix/store/${ocBin}/bin/opencode serve --hostname 0.0.0.0 --port 4096
          '' ];
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
          startupProbe = {
            httpGet = { path = "/doc"; port = "http"; };
            initialDelaySeconds = 5;
            periodSeconds = 5;
            failureThreshold = 60;
          };
          readinessProbe = {
            httpGet = { path = "/doc"; port = "http"; };
            periodSeconds = 10;
          };
          livenessProbe = {
            httpGet = { path = "/doc"; port = "http"; };
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
        }];

        volumes = [
          nixVol.volume
          { name = "home"; emptyDir = {}; }
        ];
      };
    };
  };
}
