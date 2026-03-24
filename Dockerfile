FROM ruby:3.3-alpine

RUN apk add --no-cache curl xz zstd bzip2 nix \
    --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

RUN apk add --no-cache build-base ruby-dev linux-headers \
 && gem install kubeclient async async-http --no-document \
 && apk del build-base ruby-dev linux-headers

COPY store-daemon.rb /bin/store-daemon
RUN chmod +x /bin/store-daemon

ENTRYPOINT ["ruby", "/bin/store-daemon"]
