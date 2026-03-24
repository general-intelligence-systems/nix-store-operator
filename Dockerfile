FROM ruby:3.3-alpine

RUN apk add --no-cache fuse ca-certificates \
 && gem install rfuse --no-document \
 && echo "user_allow_other" > /etc/fuse.conf

ADD https://github.com/simonfxr/nix-download/releases/download/v0.2.0/nix-download_0.2.0_linux_amd64 /usr/local/bin/nix-download
RUN chmod +x /usr/local/bin/nix-download

COPY fuse-daemon.rb /bin/fuse-daemon
RUN chmod +x /bin/fuse-daemon

RUN mkdir -p /data/store

ENTRYPOINT ["ruby", "/bin/fuse-daemon"]
