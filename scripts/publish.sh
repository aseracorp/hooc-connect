#!/usr/bin/env bash
# Publish the HOOC Connect multi-arch images to ghcr.io/aseracorp/hooc-connect.
# Daemonless: uses crane (https://github.com/google/go-containerregistry) only.
#
# Requirements:
#   - crane in PATH (or set CRANE=/path/to/crane)
#   - GHCR_TOKEN: GitHub PAT with write:packages
#   - GHCR_USER:  GitHub username owning the token
#   - HOOC_ACCESS_TOKEN: Hooc API token
#
set -euo pipefail

CRANE="${CRANE:-crane}"
GHCR_USER="${GHCR_USER:-}"
: "${GHCR_TOKEN:?Set GHCR_TOKEN to a PAT with write:packages}"
: "${GHCR_USER:?Set GHCR_USER}"
: "${HOOC_ACCESS_TOKEN:?Set HOOC_ACCESS_TOKEN}"

REG="ghcr.io/aseracorp/hooc-connect"
V="1.1.0"
API="https://api.hooc.me/embedded-gateway/v1/binary?os=LINUX&package=DOCKER_IMAGE&access_token=${HOOC_ACCESS_TOKEN}"

mkdir -p work && cd work

# 1) fetch the docker-save tarballs (AMD64 + ARM; X86 best-effort)
fetch() {
  arch="$1"; out="$2"
  if curl -L --fail -sS -o "$out" "${API}&arch=${arch}"; then
    echo "fetched ${arch}: $(stat -c%s "$out") bytes"
  else
    echo "WARN: ${arch} not available from Hooc (skipping)"
  fi
}
fetch AMD64  HOOC_AMD64.tar
fetch ARM_V8  HOOC_ARM_V8.tar
fetch ARM_V7  HOOC_ARM_V7.tar
fetch ARM_V6  HOOC_ARM_V6.tar
fetch X86     HOOC_X86.tar

# 2) patch config.json so platforms are unambiguous (arm64 / arm v7 / arm v6 / amd64 / 386)
python3 - <<'PYEOF'
import tarfile, json, io, os
archmap = {
    'ARM_V8': ('arm64', None), 'ARM_V7': ('arm', 'v7'), 'ARM_V6': ('arm', 'v6'),
    'AMD64':  ('amd64', None),
}
if os.path.exists('HOOC_X86.tar'):
    archmap['X86'] = ('386', None)
for arch, (a, v) in archmap.items():
    src = f'HOOC_{arch}.tar'; dst = f'patched_{arch}.tar'
    if not os.path.exists(src):
        continue
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
MANIFESTS=()
for arch in ARM_V8 ARM_V7 ARM_V6 AMD64; do
  [ -f "patched_${arch}.tar" ] || continue
  case "$arch" in
    ARM_V8) tag="arm64";;
    ARM_V7) tag="armv7";;
    ARM_V6) tag="armv6";;
    AMD64)  tag="amd64";;
  esac
  "$CRANE" push "patched_${arch}.tar" "$REG:${tag}-$V"
  MANIFESTS+=("$REG:${tag}-$V")
done
if [ -f patched_X86.tar ]; then
  "$CRANE" push patched_X86.tar "$REG:x86-$V"
  MANIFESTS+=("$REG:x86-$V")
fi

# 4) multi-arch manifest (index) tags
ARGS=()
for m in "${MANIFESTS[@]}"; do ARGS+=(-m "$m"); done
"$CRANE" index append --docker-empty-base "${ARGS[@]}" -t "$REG:$V"
"$CRANE" index append --docker-empty-base "${ARGS[@]}" -t "$REG:latest"

echo "done: $REG ($V + latest) -> ${MANIFESTS[*]}"
