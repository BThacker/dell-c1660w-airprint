# Dell C1660w AirPrint bridge

Print to a Dell C1660w from iPhone, iPad, and any AirPrint client.

The C1660w cannot speak AirPrint: it only understands Dell's proprietary HBPL1
over raw TCP (port 9100), and that is fixed in firmware. This project runs
[CUPS](https://www.cups.org/) in Docker, converts incoming jobs to HBPL1 with
the Linux-native `foo2hbpl1` encoder from [foo2zjs](https://github.com/mikerr/foo2zjs),
and relays them to the printer. AirPrint discovery is published by the host's
existing Avahi, so no multicast mDNS runs inside the container.

```
 iOS / macOS ──AirPrint (IPP, PDF)──▶ host Avahi advertisement
                                            │
                                            ▼
                              host:631 ─▶ CUPS container ──HBPL1 (TCP 9100)──▶ Dell C1660w
```

## Requirements

- A Linux Docker host on the same LAN as the printer.
- Docker Engine with the Compose plugin.
- `avahi-daemon` running on the host (typical on most desktop Linux installs).
- A reachable printer address. Give the printer a **static IP or DHCP
  reservation**, since the queue points at it directly.
- Nothing else may already publish TCP port 631 on the host (no host CUPS).

> Docker Desktop on macOS/Windows or Synology/QNAP may work, but host networking
> and mDNS across Docker's bridge are unreliable there. This setup targets a
> plain Linux host, where the container uses bridge networking and the **host**
> Avahi does the advertising.

## Quick start

1. Edit `compose.yaml` and set `PRINTER_IP` to your printer's address
   (and `PAGE_SIZE`/`COLOR_MODE` if you like).

2. Build and start CUPS:

   ```sh
   docker compose up -d --build
   docker compose logs -f cups
   ```

   Wait for `CUPS is ready on port 631`.

3. Publish the queue to AirPrint clients using the host's Avahi:

   ```sh
   ./host/install-airprint.sh
   ```

4. On your iPhone/iPad, open a document, choose **Print**, and select
   **Dell C1660w Native**.

### Prebuilt image (no local build)

A multi-arch (`linux/amd64`, `linux/arm64`) image is published to GHCR by
`.github/workflows/publish.yml`. Make the package public once under
**Package settings → Change visibility → Public**, then use `compose.ghcr.yaml`
(or paste its entire contents into a Dockge stack — keep the top-level
`volumes:` section):

```sh
docker pull ghcr.io/bthacker/dell-c1660w-airprint:latest
```

## Configuration

Set these under `environment:` in `compose.yaml`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `PRINTER_IP` | *(required)* | Printer LAN address or hostname |
| `PRINTER_PORT` | `9100` | Raw print port |
| `QUEUE` | `dell-c1660w` | CUPS queue name (must match `rp=` in the Avahi file) |
| `PAGE_SIZE` | `Letter` | `Letter` or `A4` |
| `COLOR_MODE` | `Color` | `Color` or `Monochrome` |
| `DESCRIPTION` | `Dell C1660w Native` | Queue description |
| `LOCATION` | `Docker host` | Queue location |
| `PPD` | `/usr/share/ppd/Dell-C1660.ppd` | Printer description file |
| `NAME` *(host script)* | `dell-c1660w` | Avahi service file name |

CUPS state lives in the `cups-etc` volume, so the queue survives restarts.
To re-create the queue after changing `PRINTER_IP`, remove the volume:
`docker compose down -v && docker compose up -d --build`.

## Verify and troubleshoot

Test the printer with a CUPS job (bypasses AirPrint):

```sh
printf 'Hello from CUPS\n' | docker compose exec -T cups \
  lp -d dell-c1660w -o ColorMode=Color -
docker compose exec cups lpstat -l -p
```

Check discovery from the host:

```sh
avahi-browse -rt _ipp._tcp
```

- **iOS does not show the printer.** Confirm `avahi-browse` lists it, the phone
  is on the same VLAN/subnet, and client isolation/guest Wi-Fi is off. Some
  networks block multicast (5353/udp). Also confirm `rp=printers/<QUEUE>`
  matches the queue name.
- **Nothing prints / job stopped.** `docker compose logs -f cups`, then resend.
  Confirm the printer is reachable: `docker compose exec cups ping -c1 $PRINTER_IP`.
- **Port 631 already in use.** Stop the host CUPS (`sudo systemctl stop cups`)
  or change the published port and the Avahi `<port>`.
- **AirPrint lists it but stalls.** This bridge advertises PDF, not Apple
  Raster (URF); leave `pdl=application/pdf` as-is.
- **Wrong language / garbled output.** The C1660w needs 600 dpi, Letter/A4.
  Use the provided PPD and defaults.

## Security

CUPS is reachable on TCP 631 by anything that can reach the host, with no
authentication (as normal for IPP printing). Keep it on a trusted LAN, or
restrict the published port with a host firewall. Do not expose it to the
internet.

## License and attribution

GPL-2.0-or-later. This project only provides packaging and configuration; it
builds and bundles [foo2zjs](https://github.com/mikerr/foo2zjs) (GPL-2.0-or-later),
whose `foo2hbpl1` encoder originated with Dave Coffin and was extended by Rick
Richardson. See `LICENSE`.

Not affiliated with or endorsed by Dell. Provided as is, without warranty; use
at your own risk.

> Status: packaging is untested against a physical printer from this repository.
> The underlying `foo2hbpl1` driver is the same one used by the macOS project
> [dell-c1660w-macos](https://github.com/BThacker/dell-c1660w-macos).
