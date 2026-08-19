#!/bin/bash
set -euo pipefail

/usr/sbin/nft delete table inet medha_worker 2>/dev/null || true
/usr/sbin/nft delete table inet medha_storage 2>/dev/null || true
exec /usr/sbin/nft -f /etc/medha/firewall.nft
