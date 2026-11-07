#!/usr/bin/env bash
# Isolated runtime; no model credentials, proxies or search-provider subscriptions.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
command -v npx >/dev/null
npm install --prefix /opt/cardscout/retrieval --omit=dev --save-exact playwright@1.64.1
PLAYWRIGHT_BROWSERS_PATH=/opt/cardscout/retrieval/browsers \
  /opt/cardscout/retrieval/node_modules/.bin/playwright install chromium --with-deps
# Chromium's sandbox needs a narrow executable allowance on Ubuntu 24.04.
# The allowed binary and all parent folders are root-owned, not service-writable.
browser_bin=/opt/cardscout/retrieval/browsers/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell
[[ -x $browser_bin ]]
chown -R root:root /opt/cardscout/retrieval
chmod -R go-w /opt/cardscout/retrieval
if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true) == 1 ]]; then
  cat > /etc/apparmor.d/cardscout-chromium <<EOF
abi <abi/4.0>,
include <tunables/global>
profile cardscout-chromium $browser_bin flags=(unconfined) {
  userns,
}
EOF
  apparmor_parser -r /etc/apparmor.d/cardscout-chromium
fi
echo 'Retrieval browser installed with Chromium sandbox enabled.'
