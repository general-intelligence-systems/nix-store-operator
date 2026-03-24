{
  description = "OpenCode server deployed via fuse-daemon";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-store-operator.url = "github:general-intelligence-systems/nix-store-operator";
    opencode.url = "github:AodhanHayter/opencode-flake";
  };

  outputs = { self, nixpkgs, nix-store-operator, opencode, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nix-store-operator.lib;
      oc = opencode.packages.${system}.default;
      ocBin = builtins.baseNameOf (builtins.unsafeDiscardStringContext (toString oc));
      image = "opencode-fuse-daemon:latest";

      manifests = {
        namespace  = import ./manifests/namespace.nix;
        deployment = import ./manifests/deployment.nix { inherit lib image ocBin; };
        service    = import ./manifests/service.nix;
        secret     = import ./manifests/secret.nix;
      };
    in {
      packages.${system} = {
        default = oc;

        # Whitelist: full closure (bake into image at /etc/nix/store-whitelist)
        whitelist = lib.mkWhitelist { inherit pkgs; } oc;

        # App store: non-cached store paths (bake into image at /data/store/)
        app-store = lib.mkAppStore { inherit pkgs; } oc;

        # Kubernetes manifests as JSON
        manifests = pkgs.runCommand "opencode-manifests" {} ''
          mkdir -p $out
          ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: value:
            "cp ${pkgs.writeText "${name}.json" (builtins.toJSON value)} $out/${name}.json"
          ) manifests))}
        '';
      };
    };
}
