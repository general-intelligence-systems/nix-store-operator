FROM nixos/nix:latest AS build

RUN nix-channel --update \
 && nix-env -iA nixpkgs.ruby nixpkgs.gcc nixpkgs.gnumake

RUN gem install kubeclient --no-document

FROM nixos/nix:latest

RUN nix-channel --update \
 && nix-env -iA nixpkgs.ruby nixpkgs.cacert

COPY --from=build /root/.local/share/gem /root/.local/share/gem

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
