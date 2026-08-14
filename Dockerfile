FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    git \
    jq \
    sqlite3 \
    luajit \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lunet-backproxy

COPY . .

RUN chmod +x scripts/*.sh scripts/docker/*.sh && \
    scripts/setup-lunet.sh

CMD ["bash", "-lc", "scripts/docker/run-dmz.sh"]
