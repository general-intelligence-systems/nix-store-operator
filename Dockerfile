FROM nixos/nix:latest

RUN nix-channel --update \
 && nix-env -iA nixpkgs.ruby nixpkgs.cacert

RUN gem install kubeclient --no-document

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
