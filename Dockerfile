# Stage 1: Compile native gem extensions
FROM ruby:slim AS gems
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*
RUN gem install kubeclient --no-document

# Stage 2: Extract nix binary and its store closure
FROM nixos/nix:latest AS nix
RUN nix-store -qR $(which nix) | tar -cf /nix-closure.tar -T - -C /

# Stage 3: Final image
FROM ruby:slim

RUN apt-get update && apt-get install -y ca-certificates xz-utils && rm -rf /var/lib/apt/lists/*

COPY --from=nix /nix-closure.tar /tmp/nix-closure.tar
RUN tar -xf /tmp/nix-closure.tar -C / && rm /tmp/nix-closure.tar
COPY --from=nix /root/.nix-profile /root/.nix-profile

COPY --from=gems /usr/local/bundle /usr/local/bundle

ENV PATH="/root/.nix-profile/bin:${PATH}"
ENV NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
