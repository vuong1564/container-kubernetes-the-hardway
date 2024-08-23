FROM alpine:3.15.4

RUN apk add --no-cache git openssh-client \
    && mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com >> ~/.ssh/known_hosts

RUN --mount=type=ssh git clone git@github.com:cucxabong/container-the-hardway.git
