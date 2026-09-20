#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Publish the containerized CUPS queue to iOS/macOS via the host's Avahi.
# Run this on the Docker host (needs sudo); it does not touch the container.
set -eu

QUEUE="${QUEUE:-dell-c1660w}"
NAME="${NAME:-dell-c1660w}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$HERE/dell-c1660w.service"
DEST="/etc/avahi/services/${NAME}.service"

if ! command -v avahi-daemon >/dev/null 2>&1; then
  echo "avahi-daemon is not installed on this host." >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

sed "s|rp=printers/[^<]*|rp=printers/${QUEUE}|" "$TEMPLATE" | sudo tee "$DEST" >/dev/null
sudo systemctl reload avahi-daemon 2>/dev/null || sudo systemctl restart avahi-daemon

echo "Installed $DEST"
echo "Verify with: avahi-browse -rt _ipp._tcp"
