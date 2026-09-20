# syntax=docker/dockerfile:1
# SPDX-License-Identifier: GPL-2.0-or-later
#
# CUPS + AirPrint bridge for the Dell C1660w.
#
# The C1660w understands only HBPL1 over raw TCP (port 9100); it cannot speak
# IPP/AirPrint itself. This image runs CUPS, converts incoming jobs to HBPL1
# with the Linux-native foo2hbpl1 encoder from upstream foo2zjs, and relays
# them to the printer. AirPrint discovery is published by the host's Avahi
# (see host/), so no mDNS runs inside this container.

FROM debian:bookworm-slim AS builder

ARG FOO2ZJS_REPO=https://github.com/mikerr/foo2zjs
ARG FOO2ZJS_REF=5bf0142d1e3d4363684608ac42933510d3b66e27

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone "$FOO2ZJS_REPO" . \
 && git checkout -q "$FOO2ZJS_REF" \
 && make foo2hbpl1 foo2hbpl1-wrapper \
 && install -D -m 0755 foo2hbpl1          /out/usr/bin/foo2hbpl1 \
 && install -D -m 0755 foo2hbpl1-wrapper  /out/usr/bin/foo2hbpl1-wrapper \
 && install -D -m 0755 foo2zjs-pstops.sh  /out/usr/bin/foo2zjs-pstops \
 && install -D -m 0644 PPD/Dell-C1660.ppd /out/usr/share/ppd/Dell-C1660.ppd


FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        cups \
        cups-filters \
        cups-ipp-utils \
        ghostscript \
        dc \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/ /
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 631
VOLUME ["/etc/cups"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
