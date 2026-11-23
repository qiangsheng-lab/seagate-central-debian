FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends squashfs-tools e2fsprogs \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY scripts/unpack.sh scripts/pack.sh scripts/check-space.sh /recipe/
