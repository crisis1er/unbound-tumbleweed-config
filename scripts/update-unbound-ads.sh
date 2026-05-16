#!/bin/bash
set -euo pipefail

DEST="/etc/unbound/local.d/unbound_add_servers.conf"
TMP="/tmp/oisd_raw.conf"
URL="https://big.oisd.nl/unbound"

# Téléchargement OISD big (format Unbound natif — always_null)
curl -fsSo "$TMP" "$URL"

# Suppression du bloc server: + ajout AAAA ::1 + filtrage des domaines dans zzz-overrides.conf
python3 - << 'PYEOF'
import re

OVERRIDES = "/etc/unbound/local.d/zzz-overrides.conf"
src = "/tmp/oisd_raw.conf"
dst = "/etc/unbound/local.d/unbound_add_servers.conf"

override_domains = set()
with open(OVERRIDES) as f:
    for line in f:
        m = re.match(r'local-zone:\s+"([^"]+)"', line.strip())
        if m:
            override_domains.add(m.group(1))

with open(src) as fin, open(dst, "w") as fout:
    for line in fin:
        if line.strip() == "server:":
            continue
        if any(f'"{d}"' in line or f'"{d} ' in line for d in override_domains):
            continue
        fout.write(line)
        if 'local-data:' in line and ' A 127.0.0.1"' in line:
            fout.write(line.replace(' A 127.0.0.1"', ' AAAA ::1"'))
PYEOF

rm -f "$TMP"

# Restaure le contexte SELinux (named_conf_t) au cas où le fichier aurait été recréé
restorecon -v /etc/unbound/local.d/unbound_add_servers.conf

# Redémarrage Unbound pour charger les nouvelles local-zones
systemctl restart unbound.service
