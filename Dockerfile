FROM nixos/nix:latest

RUN nix-channel --update \
 && nix-env -iA nixpkgs.ruby nixpkgs.cacert nixpkgs.gcc nixpkgs.gnumake \
 && gem install kubeclient --no-document \
 && nix-env -e gcc gnumake \
 && nix-collect-garbage -d \
 && rm -rf /root/.cache /root/.nix-defexpr /root/.nix-channels

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
