FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    git \
    jq \
    sqlite3 \
    xmake \
    build-essential \
    pkg-config \
    libuv1-dev \
    luajit \
    libluajit-5.1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lunet-backproxy

COPY . .

RUN chmod +x scripts/*.sh scripts/docker/*.sh && \
    scripts/setup-lunet.sh

ENV LUNET_VERSION=v0.1.0

CMD ["bash", "-lc", "scripts/docker/run-dmz.sh"]
