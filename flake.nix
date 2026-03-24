{
  description = "FUSE-based lazy /nix/store for Kubernetes pods";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }: {
    lib = {

      # mkWhitelist - file listing every /nix/store path in a derivation's
      # transitive closure. Bake this into the image at /etc/nix/store-whitelist.
      mkWhitelist = { pkgs }: drvs:
        let drvList = if builtins.isList drvs then drvs else [ drvs ];
        in pkgs.runCommand "store-whitelist" {} ''
          cp "${pkgs.closureInfo { rootPaths = drvList; }}/store-paths" $out
        '';

      # mkAppStore - directory containing only the given derivations laid out
      # as <hash>-<name>/ entries. These are the non-cached paths baked into
      # the image at /data/store/. Cached deps are fetched lazily at runtime.
      mkAppStore = { pkgs }: drvs:
        let drvList = if builtins.isList drvs then drvs else [ drvs ];
        in pkgs.runCommand "app-store" {} ''
          mkdir -p $out
          ${builtins.concatStringsSep "\n" (map (drv:
            "cp -a ${drv} $out/${builtins.baseNameOf (builtins.unsafeDiscardStringContext (toString drv))}"
          ) drvList)}
        '';

      # mkSidecar - native sidecar container spec (initContainer with
      # restartPolicy: Always). Guaranteed to start before app containers
      # and run for the pod's lifetime. Requires Kubernetes >= 1.28.
      mkSidecar = { image, cache ? "https://cache.nixos.org" }: {
        name = "fuse-daemon";
        inherit image;
        restartPolicy = "Always";
        securityContext.privileged = true;
        command = [ "ruby" "/bin/fuse-daemon"
          "--root"      "/data/store"
          "--mount"     "/mnt/nix/store"
          "--whitelist" "/etc/nix/store-whitelist"
          "--cache"     cache
        ];
        volumeMounts = [{
          name = "nix";
          mountPath = "/mnt/nix";
          mountPropagation = "Bidirectional";
        }];
      };

      # mkNixVolume - the shared emptyDir volume and app-side mount for
      # /nix/store. Use in your pod spec alongside mkSidecar.
      mkNixVolume = {
        volume = { name = "nix"; emptyDir = {}; };
        mount = {
          name = "nix";
          mountPath = "/nix";
          mountPropagation = "HostToContainer";
        };
      };

      # Deprecated: kept for backwards compatibility
      mkStorePaths = { pkgs }: drv:
        "${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths";
    };
  };
}
