#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

if [ -z "${PRINTER_IP:-}" ]; then
  echo "PRINTER_IP is not set (the printer LAN address)." >&2
  exit 1
fi
QUEUE="${QUEUE:-dell-c1660w}"
DESCRIPTION="${DESCRIPTION:-Dell C1660w Native}"
LOCATION="${LOCATION:-Docker host}"
PPD="${PPD:-/usr/share/ppd/Dell-C1660.ppd}"
PAGE_SIZE="${PAGE_SIZE:-Letter}"
COLOR_MODE="${COLOR_MODE:-Color}"
PRINTER_PORT="${PRINTER_PORT:-9100}"

# Write a known-good cupsd.conf: listen on all interfaces and allow any client
# (the container is only reachable through the published port). This avoids
# relying on the distro's default access rules, which can reject IPP/HTTP with
# 403 and make AirPrint clients report the printer as offline.
mkdir -p /run/cups
cat > /etc/cups/cupsd.conf <<'EOF'
LogLevel warn
MaxLogSize 0
Listen 0.0.0.0:631
Listen /run/cups/cups.sock
Browsing Off
DefaultAuthType Basic
WebInterface Yes
ServerAlias *

<Location />
  Order allow,deny
  Allow all
</Location>

<Location /admin>
  Order allow,deny
  Allow all
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow all
</Location>
EOF

echo "Starting cupsd..."
/usr/sbin/cupsd -f &
cupsd_pid=$!
trap 'kill -TERM "$cupsd_pid" 2>/dev/null || true' TERM INT

i=0
until lpstat -r >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "cupsd failed to start" >&2
    exit 1
  fi
  sleep 0.5
done

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  echo "Queue '$QUEUE' already exists."
else
  echo "Creating queue '$QUEUE' -> socket://${PRINTER_IP}:${PRINTER_PORT}"
  lpadmin -p "$QUEUE" -E \
    -v "socket://${PRINTER_IP}:${PRINTER_PORT}" \
    -P "$PPD" \
    -D "$DESCRIPTION" \
    -L "$LOCATION" \
    -o printer-is-shared=true \
    -o PageSize="$PAGE_SIZE" \
    -o ColorMode="$COLOR_MODE" \
    -o printer-error-policy=stop-printer
fi

echo "CUPS is ready on port 631 (queue: $QUEUE)."
echo "Run host/install-airprint.sh on the Docker host to advertise it via Avahi."

wait "$cupsd_pid"
