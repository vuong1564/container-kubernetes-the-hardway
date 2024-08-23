FROM alpine:3.15.4

ARG SSH_PRIVATE_KEY

RUN apk add --no-cache git openssh-client \
    && mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com >> ~/.ssh/known_hosts \
    && echo "${SSH_PRIVATE_KEY}" > ~/.ssh/id_rsa \
    && chmod 400 ~/.ssh/id_rsa \
    && git clone git@github.com:cucxabong/container-the-hardway.git \
    && rm -f ~/.ssh/id_rsa
