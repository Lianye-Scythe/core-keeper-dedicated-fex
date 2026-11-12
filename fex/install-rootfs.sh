#!/usr/bin/env bash
set -Eeuo pipefail
# Use the official fetcher's manifest and XXH3-64 integrity check, not an old
# third-party RootFS URL. Record SHA-256 as additional build provenance.
destination="${1:?Usage: install-rootfs.sh DESTINATION or --metadata-only}"
selection="$(curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
    --connect-timeout 15 --max-time 60 https://rootfs.fex-emu.gg/RootFS_links.json \
    | jq -cer '.v1 | to_entries | map(select(.value.DistroMatch == "ubuntu"
    and .value.DistroVersion == "24.04" and .value.Type == "squashfs"))
    | if length == 1 then .[0].value else error("Ambiguous Ubuntu 24.04 RootFS") end')"
url="$(jq -r '.URL' <<<"${selection}")"
hash="$(jq -r '.Hash' <<<"${selection}")"
[[ "${url}" =~ ^https://rootfs\.fex-emu\.gg/Ubuntu_24_04/[0-9-]+/Ubuntu_24_04\.sqsh$ ]]
[[ "${hash}" =~ ^[0-9a-fA-F]{1,16}$ ]]
if [[ "${destination}" == --metadata-only ]]; then
    jq -c '{URL,Hash}' <<<"${selection}"
    exit 0
fi
curl --fail --location --retry 3 --connect-timeout 15 --max-time 1200 \
    "${url}" -o /tmp/fex-rootfs.sqsh
expected="$(printf '%016x' "0x${hash}")"
actual="$(xxhsum -H3 /tmp/fex-rootfs.sqsh | awk '{print $NF}')"
[[ "${actual,,}" == "${expected,,}" ]] || {
    echo "RootFS XXH3-64 mismatch: expected ${expected}, received ${actual}" >&2
    exit 1
}
sha="$(sha256sum /tmp/fex-rootfs.sqsh | cut -d ' ' -f 1)"
jq -n --argjson source "${selection}" --arg sha256 "${sha}" \
    '{source:$source,sha256:$sha256}' > /opt/fex-rootfs-source.json
unsquashfs -no-progress -d "${destination}" /tmp/fex-rootfs.sqsh
rm -f /tmp/fex-rootfs.sqsh
