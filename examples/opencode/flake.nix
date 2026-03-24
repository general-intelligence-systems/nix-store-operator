{
  description = "OpenCode server deployed via fuse-daemon";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    opencode.url = "github:AodhanHayter/opencode-flake";
  };

  outputs = { self, nixpkgs, opencode, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      oc = opencode.packages.${system}.default;

      manifests = {
        namespace  = import ./manifests/namespace.nix;
        deployment = import ./manifests/deployment.nix;
        service    = import ./manifests/service.nix;
        secret     = import ./manifests/secret.nix;
      };
    in {
      packages.${system} = {
        default = oc;
        manifests = pkgs.runCommand "opencode-manifests" {} ''
          mkdir -p $out
          ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: value:
            "cp ${pkgs.writeText "${name}.json" (builtins.toJSON value)} $out/${name}.json"
          ) manifests))}
        '';
      };
    };
}
