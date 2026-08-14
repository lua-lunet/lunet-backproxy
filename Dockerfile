FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    git \
    jq \
    libsodium23 \
    libuv1 \
    sqlite3 \
    luajit \
    && ln -s libsodium.so.23 "$(dirname "$(ldconfig -p | awk '/libsodium\.so\.23/{print $NF; exit}')")/libsodium.so" \
    && ldconfig \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lunet-backproxy

COPY . .

RUN chmod +x scripts/*.sh scripts/docker/*.sh && \
    scripts/setup-lunet.sh

CMD ["bash", "-lc", "scripts/docker/run-dmz.sh"]
