# Stage 1: Compile native gem extensions
FROM ruby:slim AS gems
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*
RUN gem install kubeclient --no-document

# Stage 2: Keep only the nix binary's store closure
FROM nixos/nix:latest AS nix
ENV PATH="/root/.nix-profile/bin:${PATH}"
RUN nix-store -qR $(which nix) > /keep.txt \
 && find /nix/store -maxdepth 1 -mindepth 1 | while read p; do \
      grep -qx "$p" /keep.txt || rm -rf "$p"; \
    done

# Stage 3: Final image
FROM ruby:slim

RUN apt-get update && apt-get install -y ca-certificates xz-utils && rm -rf /var/lib/apt/lists/*

COPY --from=nix /nix/store /nix/store
COPY --from=nix /root/.nix-profile /root/.nix-profile

COPY --from=gems /usr/local/bundle /usr/local/bundle

ENV PATH="/root/.nix-profile/bin:${PATH}"
ENV NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
