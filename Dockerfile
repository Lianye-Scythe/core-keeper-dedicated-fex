# Native ARM64 host with an extracted x86-64 guest RootFS; no privileged mounts.
ARG ROOTFS_BASE=ubuntu:24.04
ARG RUNTIME_BASE=ubuntu:26.04
FROM ${ROOTFS_BASE} AS rootfs
ARG APT_REFRESH_NONCE=manual
RUN apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o APT::Update::Error-Mode=any update \
    && apt-get install -y --no-install-recommends \
    ca-certificates curl jq squashfs-tools xxhash \
    && rm -rf /var/lib/apt/lists/*
COPY fex/install-rootfs.sh /usr/local/bin/install-fex-rootfs
RUN echo "Refreshing official RootFS manifest: ${APT_REFRESH_NONCE}" \
    && bash /usr/local/bin/install-fex-rootfs /opt/fex-rootfs

FROM ${RUNTIME_BASE}
ARG TARGETARCH
ARG APT_REFRESH_NONCE=manual
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
RUN test "${TARGETARCH}" = arm64
ENV DEBIAN_FRONTEND=noninteractive
COPY fex/fex-ppa.sources /tmp/fex-ppa.sources
RUN echo "Refreshing FEX packages: ${APT_REFRESH_NONCE}" \
    && apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o APT::Update::Error-Mode=any update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl python3 xvfb libxi6 tini \
       tzdata gosu jo jq gettext-base unzip wget libdbus-1-3 libxcursor1 \
       libxinerama1 libxss1 libgl1-mesa-dri libglx-mesa0 libegl1 libvulkan1 \
    && mv /tmp/fex-ppa.sources /etc/apt/sources.list.d/fex-ppa.sources \
    && apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 \
       -o APT::Update::Error-Mode=any update \
    && apt-get install -y --no-install-recommends fex-emu-armv8.2 \
    && apt-get -o Dpkg::Options::="--force-confold" upgrade -y --with-new-pkgs \
    && rm -rf /var/lib/apt/lists/*
COPY --from=rootfs /opt/fex-rootfs /opt/fex-rootfs
COPY --from=rootfs /opt/fex-rootfs-source.json /opt/fex-rootfs-source.json
RUN curl --fail --location --retry 3 \
       "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-arm64.zip" \
       -o /tmp/depot.zip \
    && unzip /tmp/depot.zip -d /opt/depot-downloader \
    && chmod +x /opt/depot-downloader/DepotDownloader \
    && ln -s /opt/depot-downloader/DepotDownloader /usr/local/bin/DepotDownloader \
    && printf '%s\n' "${DEPOT_DOWNLOADER_VERSION}" > /opt/depot-downloader-version \
    && rm /tmp/depot.zip
ENV USER=steam HOMEDIR=/home/steam HOME=/home/steam \
    STEAMAPPID=1007 STEAMAPPID_TOOL=1963720 STEAMAPP=core-keeper \
    STEAMAPPDIR=/home/steam/core-keeper-dedicated \
    STEAMAPPDATADIR=/home/steam/core-keeper-data \
    STEAMCMDDIR=/home/steam/steamcmd SCRIPTSDIR=/home/steam/scripts \
    MODSDIR=/home/steam/core-keeper-dedicated/CoreKeeperServer_Data/StreamingAssets/Mods \
    COREKEEPER_RUNTIME=fex FEX_ROOTFS=/opt/fex-rootfs \
    FEX_MULTIBLOCK=1 FEX_MAXINST=16 \
    FEX_APP_CACHE_LOCATION=/home/steam/.cache/fex/ \
    PUID=1000 PGID=1000 USE_DEPOT_DOWNLOADER=true DEBUG=false \
    WORLD_INDEX=0 WORLD_NAME="Core Keeper Server" WORLD_SEED="" WORLD_MODE=0 \
    HASHED_WORLD_SEED="" GAME_ID="" MAX_PLAYERS=8 SEASON="" \
    SERVER_IP="" SERVER_PORT="" PASSWORD="" ACTIVATE_CONTENT="" \
    ACTIVATE_ALL_CONTENT=false ALLOW_ONLY_PLATFORM="" \
    UPDATE_GATE_ENABLED=false UPDATE_PERMIT_FILE=/run/corekeeper-update/apply-update \
    UPDATE_PERMIT_MAX_AGE_SECONDS=3600 \
    DISCORD_WEBHOOK_URL="" DISCORD_PLAYER_JOIN_ENABLED=false \
    DISCORD_PLAYER_LEAVE_ENABLED=false DISCORD_SERVER_START_ENABLED=false \
    DISCORD_SERVER_STOP_ENABLED=false MODS_ENABLED=false MODIO_API_KEY="" MODIO_API_URL="" MODS="" \
    MESA_SHADER_CACHE_MAX_SIZE=512M
RUN userdel -r ubuntu \
    && useradd -m -u 1000 steam \
    && mkdir -p /tmp/.X11-unix "${STEAMAPPDIR}" "${STEAMAPPDATADIR}" \
       "${STEAMCMDDIR}" /home/steam/.steam/sdk64 /home/steam/.cache/fex \
    && chmod 1777 /tmp/.X11-unix \
    && ln -s "${STEAMAPPDIR}/linux64" "${STEAMCMDDIR}/linux64" \
    && ln -s "${STEAMAPPDIR}/linux64/steamclient.so" /home/steam/.steam/sdk64/steamclient.so
COPY scripts /home/steam/scripts
COPY fex/steam-build.sh /home/steam/scripts/steam-build.sh
RUN chmod +x /home/steam/scripts/*.sh && chown -R steam:steam /home/steam
LABEL org.opencontainers.image.title="Core Keeper dedicated server (FEX ARM64)"
WORKDIR /home/steam
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "scripts/entry.sh"]
