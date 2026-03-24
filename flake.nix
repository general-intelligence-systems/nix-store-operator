{
  description = "Kubernetes operator for shared /nix/store volume mounts";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }: {
    lib = {
      # mkStorePaths - returns the path to a file containing all /nix/store
      # paths in the transitive dependency closure of a derivation.
      #
      # Usage in a consuming flake:
      #
      #   inputs.nix-store-operator.url = "github:general-intelligence-systems/nix-store-operator";
      #
      #   outputs = { self, nixpkgs, nix-store-operator, ... }:
      #     let
      #       pkgs = nixpkgs.legacyPackages.x86_64-linux;
      #       mkStorePaths = nix-store-operator.lib.mkStorePaths { inherit pkgs; };
      #     in {
      #       packages.x86_64-linux = {
      #         default = <your-app>;
      #         store-paths = mkStorePaths self.packages.x86_64-linux.default;
      #       };
      #     };
      #
      mkStorePaths = { pkgs }: drv:
        "${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths";
    };
  };
}
