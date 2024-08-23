
FROM python:3.8.13-buster

RUN apt-get update \
    && apt-get install -y \
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

COPY . /

RUN pip install -r /app/requirements.txt
RUN chown -R nobody:nogroup /app \
    && chmod +x /app/docker-entrypoint.sh

WORKDIR /app
USER nobody

ENTRYPOINT ["/app/docker-entrypoint.sh"]
