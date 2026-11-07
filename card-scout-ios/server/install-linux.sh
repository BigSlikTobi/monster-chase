#!/usr/bin/env bash
# Run on a fresh Ubuntu 24.04 server after joining Tailscale.
set -euo pipefail
if [[ $(id -u) != 0 ]]; then
    echo 'Run this installer as root.' >&2
    exit 1
fi
if [[ $# != 1 || ( $1 != --prepare && ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ) ]]; then
    echo 'Usage: sudo bash server/install-linux.sh <Tailscale-IPv4|--prepare>' >&2
    exit 1
fi
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Validate before package changes. The worker must never bind to a public address.
if [[ $1 != --prepare ]]; then
    python3 -c 'import ipaddress,sys; assert ipaddress.IPv4Address(sys.argv[1]) in ipaddress.IPv4Network("100.64.0.0/10"), "Use a Tailscale IP"' "$1"
    command -v tailscale >/dev/null
    tailscale ip -4 | awk -v expected="$1" '$0 == expected {found=1} END {exit !found}'
fi
# Preserve working runtimes on a VPS already hosting other applications.
missing_packages=()
for runtime in python3 openssl node npm; do
    if ! command -v "$runtime" >/dev/null; then
        if [[ $runtime == node ]]; then missing_packages+=(nodejs); else missing_packages+=("$runtime"); fi
    fi
done
if ! command -v bwrap >/dev/null; then missing_packages+=(bubblewrap); fi
needs_bwrap_profile=false
if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true) == 1 && ! -f /etc/apparmor.d/bwrap-userns-restrict ]]; then
    needs_bwrap_profile=true
    missing_packages+=(apparmor-profiles apparmor-utils)
fi
if (( ${#missing_packages[@]} )); then
    apt-get update
    apt-get install -y "${missing_packages[@]}"
fi
if [[ $needs_bwrap_profile == true ]]; then
    install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
    apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
fi
if ! id cardscout >/dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/cardscout --shell /usr/sbin/nologin cardscout
fi
install -d -m 0755 /opt/cardscout/service/data
install -d -o cardscout -g cardscout -m 0700 /var/lib/cardscout /var/lib/cardscout/data
# Pin the CLI to the version used to prepare this deployment. No personal Mac auth is copied.
systemctl stop cardscout.service 2>/dev/null || true
npm install --prefix /opt/cardscout --omit=dev --save-exact @openai/codex@0.160.1
# Ubuntu's namespace restrictions must work with Codex, including under the service policy.
# Fail before enabling research rather than removing the worker's read-only sandbox.
systemd-run --quiet --wait --pipe --collect --unit=cardscout-sandbox-check \
    --property=User=cardscout --property=Group=cardscout \
    --property=NoNewPrivileges=true --property=ProtectSystem=strict \
    --property=ProtectHome=true --property=PrivateTmp=true \
    --property=ReadWritePaths=/var/lib/cardscout --working-directory=/var/lib/cardscout \
    /usr/bin/env CODEX_HOME=/var/lib/cardscout/data/codex \
    /opt/cardscout/node_modules/.bin/codex --sandbox read-only sandbox /usr/bin/true
for module in reference_images scan_matches catalog_supplement server analysis api_client retrieval card_prices raw_guides schema chases cardsight cardsight_pilot linux setup; do
    install -m 0644 "$source_dir/mac/$module.py" "/opt/cardscout/service/$module.py"
done
install -m 0644 "$source_dir/mac/retrieve_page.cjs" /opt/cardscout/service/retrieve_page.cjs
install -m 0644 "$source_dir/mac/data/collections.json" /opt/cardscout/service/data/collections.json
install -m 0644 "$source_dir/mac/data/chases.json" /opt/cardscout/service/data/chases.json
install -m 0644 "$source_dir/mac/data/reference-images.json" /opt/cardscout/service/data/reference-images.json
install -m 0644 "$source_dir/mac/data/chrome-checklist-supplement.json" /opt/cardscout/service/data/chrome-checklist-supplement.json
install -m 0644 "$source_dir/mac/data/optic-checklist-supplement.json" /opt/cardscout/service/data/optic-checklist-supplement.json
install -m 0644 "$source_dir/mac/data/bowman-checklist-supplement.json" /opt/cardscout/service/data/bowman-checklist-supplement.json
install -m 0644 "$source_dir/server/cardscout.service" /etc/systemd/system/cardscout.service
systemctl daemon-reload
if [[ $1 == --prepare ]]; then
    echo 'Prepared. Join Tailscale, then rerun this installer with the Tailscale IPv4.'
    exit 0
fi
runuser -u cardscout -- python3 /opt/cardscout/service/linux.py setup --address "$1"
echo 'Installed. Run the ChatGPT login command in docs/server-setup.md, then enable the service.'
