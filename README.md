# HOOC Connect — ghcr.io/aseracorp/hooc-connect

Re-published multi-arch container image of the **Hooc Connect embedded gateway**
(original tag `hooc/connect-generic:1.1.0`), fetched from the official Hooc
binary API (`api.hooc.me/embedded-gateway/v1/binary`) and published to the
GitHub Container Registry.

| Source arch | Docker platform | Tag suffix |
|---|---|---|
| ARM_V8 | `linux/arm64` | `arm64` |
| ARM_V7 | `linux/arm/v7` | `armv7` |
| ARM_V6 | `linux/arm/v6` | `armv6` |

## Usage

```bash
# Multi-arch manifest — Docker/client picks the right platform automatically
docker pull ghcr.io/aseracorp/hooc-connect:1.1.0

# Pin a specific platform
docker pull ghcr.io/aseracorp/hooc-connect:arm64-v1.1.0
docker pull ghcr.io/aseracorp/hooc-connect:armv7-v1.1.0
docker pull ghcr.io/aseracorp/hooc-connect:armv6-v1.1.0
```

## Notes

- Original upstream image: `hooc/connect-generic:1.1.0`
- Entrypoint: `/init /bin/app_embeddedgateway`, runs as user `65534` (nobody),
  sets `HOOC_DOCKER_ENV=1`.
- These images are republished for convenience; all rights and ownership remain
  with Hooc / ASERA.
- No application source code lives in this repo — only the published container
  images. See [scripts/publish.sh](scripts/publish.sh) for the exact
  (daemonless, `crane`-based) publishing procedure.