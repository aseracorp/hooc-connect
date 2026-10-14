#!/usr/bin/env bash
# Publish the HOOC Connect multi-arch images to ghcr.io/aseracorp/hooc-connect.
# Daemonless: uses crane (https://github.com/google/go-containerregistry) only.
#
# Requirements:
#   - crane in PATH (or set CRANE=/path/to/crane)
#   - GHCR_TOKEN: GitHub PAT with write:packages (and repo write on aseracorp/hooc-connect)
#   - GHCR_USER:  GitHub username owning the token
#
set -euo pipefail

CRANE="${CRANE:-crane}"
GHCR_USER="${GHCR_USER:-}"
: "${GHCR_TOKEN:?Set GHCR_TOKEN to a PAT with write:packages}"
: "${GHCR_USER:?Set GHCR_USER}"

REG="ghcr.io/aseracorp/hooc-connect"
V="1.1.0"
API="https://api.hooc.me/embedded-gateway/v1/binary?os=LINUX&package=DOCKER_IMAGE&access_token=${HOOC_ACCESS_TOKEN:?Set HOOC_ACCESS_TOKEN}"

mkdir -p work && cd work

# 1) fetch the three docker-save tarballs
for a in ARM_V8 ARM_V7 ARM_V6; do
  curl -L --fail -sS -o "HOOC_${a}.tar" "${API}&arch=${a}"
done

# 2) patch config.json so platforms are unambiguous (arm64 / arm v7 / arm v6)
python3 - <<'PYEOF'
import tarfile, json, io
archmap = {'ARM_V8': ('arm64', None), 'ARM_V7': ('arm', 'v7'), 'ARM_V6': ('arm', 'v6')}
for arch, (a, v) in archmap.items():
    src = f'HOOC_{arch}.tar'; dst = f'patched_{arch}.tar'
    t = tarfile.open(src, 'r')
    data = json.loads(t.extractfile('manifest.json').read())
    with tarfile.open(dst, 'w') as out:
        for m in t.getmembers():
            if not m.isfile():
                out.addfile(m); continue
            payload = t.extractfile(m).read()
            if m.name == data[0]['config']:
                cfg = json.loads(payload)
                cfg['architecture'] = a
                if v: cfg['variant'] = v
                else: cfg.pop('variant', None)
                payload = json.dumps(cfg, indent=2).encode()
                m.size = len(payload)
            out.addfile(m, io.BytesIO(payload))
    print('patched', dst)
PYEOF

# 3) push
"$CRANE" auth login ghcr.io -u "$GHCR_USER" -p "$GHCR_TOKEN"
"$CRANE" push patched_ARM_V8.tar "$REG:arm64-$V"
"$CRANE" push patched_ARM_V7.tar "$REG:armv7-$V"
"$CRANE" push patched_ARM_V6.tar "$REG:armv6-$V"

# 4) multi-arch manifest (index) tags
"$CRANE" index append --docker-empty-base \
  -m "$REG:arm64-$V" -m "$REG:armv7-$V" -m "$REG:armv6-$V" -t "$REG:$V"
"$CRANE" index append --docker-empty-base \
  -m "$REG:arm64-$V" -m "$REG:armv7-$V" -m "$REG:armv6-$V" -t "$REG:latest"

echo "done: $REG ($V + latest)"
