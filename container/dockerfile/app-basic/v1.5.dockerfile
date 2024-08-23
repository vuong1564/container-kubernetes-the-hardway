FROM python:3.8.13-buster

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        jq \
        dumb-init \
        gettext-base \
        gnupg \
        jq \
        openssl \
        gcc \
        protobuf-compiler \
        unzip \
        libssl-dev \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY app/requirements.txt /app/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip pip install -r /app/requirements.txt

COPY --chown=nobody:nogroup . /

RUN chmod +x /app/docker-entrypoint.sh

WORKDIR /app
USER nobody

ENTRYPOINT ["/app/docker-entrypoint.sh"]
