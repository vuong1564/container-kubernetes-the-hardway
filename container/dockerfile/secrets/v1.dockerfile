FROM alpine:3.15.4

RUN apk add --no-cache git openssh-client \
    && mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com >> ~/.ssh/known_hosts

COPY --chmod=400 files/dockerfile-good-practices /root/.ssh/id_rsa

RUN git clone git@github.com:cucxabong/container-the-hardway.git \
    && rm -f ~/.ssh/id_rsa
