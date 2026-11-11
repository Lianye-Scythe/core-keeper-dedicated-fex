# FEX runtime notes

FEX is now the default and only supported ARM64 runtime. Build from the root
[Dockerfile](../Dockerfile). Start with the [main README](../README.md), then use
the [deployment](../docs/deployment.md), [configuration](../docs/configuration.md)
and [maintenance](../docs/maintenance.md) guides for operational details.

## Images and tags

- `ghcr.io/lianye-scythe/core-keeper-dedicated:fex`: recommended update channel.
- `:latest`: identical FEX/ARM64 channel, not the previous Box64 image.
- `:fex-<commit>`: source revision label, **not immutable** across dependency rebuilds.
- `@sha256:<digest>`: immutable image reference for reproducibility and rollback.

For older deployments, review the [migration guide](../docs/migration.md).

## Environments and provenance

The ARM64 container uses Ubuntu 26.04 LTS, while the x86-64 guest RootFS remains
on Ubuntu 24.04 LTS. These userspace environments need not match each other or
the Docker host's distribution; they share the host kernel. The official stable PPA
provides `fex-emu-armv8.2`; the official RootFS manifest supplies a validated,
extracted x86-64 guest filesystem. No privileged mount or host registration is
required. Native ARM64 DepotDownloader handles Steam downloads. The RootFS
XXH3-64 is verified; URL, hash and SHA-256 are recorded in
`/opt/fex-rootfs-source.json`. `/opt/depot-downloader-version` records the downloader.

## Translation and caches

`FEX_MULTIBLOCK=1 FEX_MAXINST=16` passed repeated isolated Core Keeper 1.3.0.4
boots and short multiplayer play on Oracle A1. Larger blocks failed during the
investigation; disabling multiblock was slower. This is a workload-specific
workaround, not FEX's default or evidence of a universally optimal setting.
Default SMC tracking and memory ordering remain enabled. Long-running stability
is still being evaluated. [Historical results](RESULTS.md) retain old comparison
evidence; they are not instructions to keep or deploy the removed Box64 runtime.

FEX cache directory: `/home/steam/.cache/fex` (`FEX_APP_CACHE_LOCATION`). This does
not enable FEX disk caches that are disabled by upstream defaults. Mesa cache is
separate at `/home/steam/.cache/mesa_shader_cache`, with a 512-MiB driver budget.
Neither cache belongs in save backups. Do not use `-nographics` for this game:
world generation needs the shipped graphical path. CPU affinity is not required.

## Validation and experiments

For parallel compatibility experiments, use independent writable game/save/cache
directories and a different Game ID. Never bind the production saves into two
running containers. Keep game build, resource limits and world contents equal
when making performance comparisons.

## Configured host deployment

[`run-production.sh`](run-production.sh) is an optional configured bootstrap.
Deployment and diagnostics share `/etc/corekeeper-update-check.json`; paths,
container name and optional resource limits are not tied to a particular VPS.
See the [deployment guide](../docs/deployment.md#configured-host-bootstrap).
It refuses to replace an existing container and never resets saves. The
scheduled updater preserves settings from the current container.

Optional host collectors and retention templates are documented under
[ops/diagnostics](../ops/diagnostics/README.md). They observe production separately
from the image and are not enabled simply by pulling a new image.

## Build and dependency policy

Daily CI compares the ARM64 Ubuntu base digests, official guest RootFS manifest,
stable DepotDownloader release/asset and image build inputs with the last
published image. If those match, it refreshes signed APT indices in a disposable
copy of that image and simulates upgrades for the installed Ubuntu/FEX packages.
It does not install packages during this check. Shell/unit checks still run;
changed inputs trigger a build and native ARM64 guest/ownership smoke tests.
Tested images are published **only from `main`**.
PRs test without publishing. Known documentation-only changes run shell/unit
checks but skip dependency resolution, image builds and publication. Runtime,
test, workflow and unknown file changes still build. Scheduled checks skip the
build and publication when all inputs match. Manual runs build by default; enable
`check_for_changes` to use the same comparison. A failed check blocks publishing;
it is not treated as unchanged. Publish a baseline with a manual build if a fork
does not have a published `:fex` image yet. The required final check remains in place.
CI resolves its download endpoints on the x64 dependency runner and passes the
addresses into isolated ARM64 builds. If runner DNS fails, HTTPS DNS is used only for
these endpoints. APT still checks the original Ubuntu and FEX archive signatures.
CI smoke tests are not full game-session tests.

Dependabot checks Docker/Actions daily; eligible patch/minor updates use
auto-merge after required checks. Major/LTS upgrades are deliberately reviewed,
not silently adopted. The GHCR package must be public for anonymous pulls, or
Docker needs registry credentials.

Pulling or publishing an image does not replace running containers or installed
host helpers. See [scheduled maintenance](../docs/maintenance.md) for deployment,
backup/rollback and updating those scripts separately.

Sources: [FEX prerequisites](https://github.com/FEX-Emu/FEX#prerequisites),
[official RootFS manifest](https://rootfs.fex-emu.gg/RootFS_links.json),
[configuration defaults](https://github.com/FEX-Emu/FEX/blob/FEX-2609.1/FEXCore/Source/Interface/Config/Config.json.in).
