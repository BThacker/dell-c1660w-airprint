# Dell C1660w AirPrint bridge

Print to a Dell C1660w from an iPhone, iPad, Mac, or any AirPrint client.

The C1660w cannot speak AirPrint: it only understands Dell's proprietary HBPL1
over raw TCP (port 9100), which is fixed in firmware. This project runs
[CUPS](https://www.cups.org/) in Docker, converts incoming jobs to HBPL1 with the
Linux-native `foo2hbpl1` encoder from [foo2zjs](https://github.com/mikerr/foo2zjs),
and relays them to the printer. AirPrint discovery is published by the host's
existing Avahi, so no multicast mDNS runs inside the container.

```
 iOS / iPadOS / macOS ── AirPrint (IPP, PDF) ──▶ host Avahi advertisement
                                                        │
                                                        ▼
                          host:631 ─▶ CUPS container ── HBPL1 (TCP 9100) ─▶ Dell C1660w
```

## Requirements

- A Linux Docker host on the same LAN as the printer.
- Docker Engine with the Compose plugin.
- `avahi-daemon` running on the host (standard on most desktop Linux installs).
- The printer's address, ideally **static or DHCP-reserved** — the queue points
  at it directly.
- Host TCP port **631 free** (no host CUPS already using it).

> This targets a plain Linux host: the container uses bridge networking and the
> **host's** Avahi does the advertising. Docker Desktop (macOS/Windows) and some
> NAS platforms don't bridge mDNS to the LAN, so discovery may not work there.

## Quick start (prebuilt image)

A multi-arch image (`linux/amd64`, `linux/arm64`) is published to GitHub
Container Registry. Make it public once under **your profile → Packages →
`dell-c1660w-airprint` → Package settings → Change visibility → Public** (or run
`docker login ghcr.io` with a token that has `read:packages`).

Create `compose.yaml` (or copy [`compose.ghcr.yaml`](compose.ghcr.yaml)):

```yaml
services:
  cups:
    image: ghcr.io/bthacker/dell-c1660w-airprint:latest
    container_name: dell-c1660w-airprint
    restart: unless-stopped
    ports:
      - "631:631"
    environment:
      PRINTER_IP: "192.168.1.50"   # <-- your printer's LAN address
      QUEUE: "dell-c1660w"
      PAGE_SIZE: "Letter"          # or A4
      COLOR_MODE: "Color"          # or Monochrome
      LOCATION: "Docker host"
    volumes:
      - cups-etc:/etc/cups

volumes:
  cups-etc:
```

Then:

```sh
docker compose up -d
docker compose logs -f cups     # wait for "CUPS is ready on port 631"
```

Publish the queue to AirPrint through the host's Avahi (run on the Docker host):

```sh
mkdir -p /opt/dell-c1660w-airprint && cd /opt/dell-c1660w-airprint
curl -fsSLO https://raw.githubusercontent.com/BThacker/dell-c1660w-airprint/main/host/install-airprint.sh
curl -fsSLO https://raw.githubusercontent.com/BThacker/dell-c1660w-airprint/main/host/dell-c1660w.service
chmod +x install-airprint.sh && ./install-airprint.sh
```

On your device, choose **Print** and select **Dell C1660w Native**.

### Using Dockge

1. **Compose → + Compose**, name the stack `dell-c1660w-airprint`.
2. Paste the full YAML above — **including the trailing `volumes:` block**, or
   Compose fails with `undefined volume cups-etc`.
3. Set `PRINTER_IP`, then **Deploy**.
4. Run the Avahi step from a host shell (Dockge can't manage host services).

## Build from source (optional)

The [Dockerfile](Dockerfile) builds the HBPL1 encoder from a pinned upstream
foo2zjs revision and needs no local toolchain beyond Docker:

```sh
git clone https://github.com/BThacker/dell-c1660w-airprint
cd dell-c1660w-airprint
# set PRINTER_IP in compose.yaml
docker compose up -d --build
./host/install-airprint.sh
```

To use a different foo2zjs revision, pass `--build-arg FOO2ZJS_REF=<commit>`.

## Configuration

Set these under `environment:` in your compose file.

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

CUPS state lives in the `cups-etc` volume, so the queue survives restarts. After
changing `PRINTER_IP`, recreate it: `docker compose down -v && docker compose up -d`.

## Verify

Print a test page without AirPrint:

```sh
printf 'Hello from CUPS\n' | docker compose exec -T cups \
  lp -d dell-c1660w -o ColorMode=Color -
docker compose exec cups lpstat -l -p
```

Confirm the bridge is advertised on the network:

```sh
avahi-browse -rt _ipp._tcp
```

## Troubleshooting

- **iOS doesn't show the printer.** Confirm `avahi-browse -rt _ipp._tcp` lists
  it; make sure the device is on the same VLAN/subnet and that guest Wi-Fi/
  client isolation is off (some networks block multicast 5353/udp). Check that
  `rp=printers/<QUEUE>` matches your `QUEUE`.
- **Job stops or nothing prints.** `docker compose logs -f cups`, then resend.
  Check reachability: `docker compose exec cups ping -c1 "$PRINTER_IP"`.
- **`port is already allocated`.** Something already binds 631 (often CUPS on
  the host); stop it or change the published port and the Avahi `<port>`.
- **`undefined volume cups-etc`.** You omitted the top-level `volumes:` block.
- **iPhone doesn't list the printer, but a Mac's `dns-sd -B _ipp._tcp` does.**
  iOS only lists `_ipp._tcp` services that carry the AirPrint TXT records
  (`URF`, `pdl=…,image/urf,…`, `kind`). Keep those in
  [`host/dell-c1660w.service`](host/dell-c1660w.service) and re-run
  `./host/install-airprint.sh` after editing. Jobs are still sent as PDF and
  converted to HBPL1 by CUPS.
- **Garbled or wrong-size output.** The C1660w expects 600 dpi on Letter/A4 —
  use the bundled PPD and defaults.

## Security

CUPS is reachable on TCP 631 by anything that can reach the host, with no
authentication (normal for IPP printing). Keep it on a trusted LAN or restrict
the port with a host firewall. Do not expose it to the internet.

## License and attribution

GPL-2.0-or-later. This repository only provides packaging and configuration; it
builds and bundles [foo2zjs](https://github.com/mikerr/foo2zjs)
(GPL-2.0-or-later), whose `foo2hbpl1` encoder originated with Dave Coffin and was
extended by Rick Richardson. See [LICENSE](LICENSE).

Not affiliated with or endorsed by Dell. Provided as is, without warranty; use at
your own risk.

The container image is built and published automatically by CI; printing through
this bridge has not been independently verified on physical hardware here. The
underlying encoder is the same one used by the macOS project
[dell-c1660w-macos](https://github.com/BThacker/dell-c1660w-macos), where color
printing was confirmed on a real C1660w.
