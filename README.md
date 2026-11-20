# nginx-live-stream

Nine isolated nginx RTMP/HLS stream containers.

- RTMP ingest is direct on host ports **1935–1943**.
- Each container serves its own HTML5 player and HLS playlist over HTTP.
- HAProxy terminates TLS on **443** and forwards each public hostname to one container.
- The container HTTP ports **18080–18088** are bound to loopback and are only for HAProxy.
- Recordings are written to one shared Docker volume.
- `/control` and `/stat` use env-driven Basic Auth when credentials are configured.

## Architecture

```text
Viewer
  https://stream01.example.com/            ─┐
  https://stream01.example.com/live/0.m3u8 ─┼─> HAProxy :443
  https://stream01.example.com/healthz     ─┘        │
                                                     └─> http://127.0.0.1:18080 ─> nginx-live-1

Publisher
  rtmp://SERVER:1935/live/0 ─────────────────────────────> nginx-live-1  (direct)
```

HAProxy owns 443 and the TLS certificates. The stream containers do not listen on 443.

## Stream mapping

| Service | Container | RTMP | Backend HTTP | Stream | HLS |
|---|---|---:|---:|---|---|
| stream-1 | nginx-live-1 | 1935 | 18080 | `0` | `/live/0.m3u8` |
| stream-2 | nginx-live-2 | 1936 | 18081 | `2` | `/live/2.m3u8` |
| stream-3 | nginx-live-3 | 1937 | 18082 | `4` | `/live/4.m3u8` |
| stream-4 | nginx-live-4 | 1938 | 18083 | `6` | `/live/6.m3u8` |
| stream-5 | nginx-live-5 | 1939 | 18084 | `8` | `/live/8.m3u8` |
| stream-6 | nginx-live-6 | 1940 | 18085 | `10` | `/live/10.m3u8` |
| stream-7 | nginx-live-7 | 1941 | 18086 | `12` | `/live/12.m3u8` |
| stream-8 | nginx-live-8 | 1942 | 18087 | `14` | `/live/14.m3u8` |
| stream-9 | nginx-live-9 | 1943 | 18088 | `16` | `/live/16.m3u8` |

The backend range starts at 18080 instead of 8080 to avoid the common `127.0.0.1:8080` conflict. Change the host mappings if your host differs.

The backend HTTP ports are not viewer URLs. Viewers use the HAProxy vhost, for example:

```text
https://stream01.example.com/
https://stream01.example.com/live/0.m3u8
https://stream01.example.com/healthz
```

## Requirements

- Docker Engine with Docker Compose v2.
- HAProxy on the same host, listening on 443.
- DNS records for the nine stream hostnames pointing at the HAProxy address.
- HAProxy certificates for those hostnames.

## Quick start

```sh
cp .env.example .env
# Edit .env and set CONTROL_PASSWORD before exposing the admin endpoints.
docker compose build
docker compose up -d
docker compose ps
```

If `CONTROL_USER` or `CONTROL_PASSWORD` is empty, `/control` returns `404` and `/stat` is reachable only from inside the container. Set a strong password before using the admin endpoints.

Check a backend directly:

```sh
curl -fsS http://127.0.0.1:18080/healthz
```

Check through HAProxy after its configuration is updated:

```sh
curl -fsS https://stream01.example.com/healthz
```

## Publish

### OBS

Use the matching RTMP port for the stream:

```text
Server:     rtmp://SERVER:1935/live
Stream key: 0
```

For the second stream:

```text
Server:     rtmp://SERVER:1936/live
Stream key: 2
```

Continue through stream 9:

| Stream | Server | Stream key |
|---:|---|---|
| 01 | `rtmp://SERVER:1935/live` | `0` |
| 02 | `rtmp://SERVER:1936/live` | `2` |
| 03 | `rtmp://SERVER:1937/live` | `4` |
| 04 | `rtmp://SERVER:1938/live` | `6` |
| 05 | `rtmp://SERVER:1939/live` | `8` |
| 06 | `rtmp://SERVER:1940/live` | `10` |
| 07 | `rtmp://SERVER:1941/live` | `12` |
| 08 | `rtmp://SERVER:1942/live` | `14` |
| 09 | `rtmp://SERVER:1943/live` | `16` |

A key other than the `name` in that container's `config/stream-N.json` is refused. The encoder sees a failed connection, and no HLS playlist is created for the wrong key. Recreate the containers after changing `name`.

### ffmpeg

```sh
ffmpeg -re \
  -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libx264 -preset veryfast -tune zerolatency -g 60 -b:v 2500k \
  -c:a aac -b:a 128k -ar 48000 \
  -f flv rtmp://SERVER:1935/live/0
```

## Admin endpoints

`/control` and `/stat` are protected by Basic Auth. The containers generate the htpasswd file from `CONTROL_USER` and `CONTROL_PASSWORD` at startup, so no credentials are stored in the image and HAProxy does not need an auth userlist.

`/control` exposes the nginx-rtmp `drop`, `record`, and `redirect` commands. All commands use GET.

Drop the publisher for stream 01:

```sh
curl -u admin 'https://stream01.example.com/control/drop/publisher?app=live&name=0'
```

Drop only the RTMP subscribers, or drop every RTMP client:

```sh
curl -u admin 'https://stream01.example.com/control/drop/subscriber?app=live&name=0'
curl -u admin 'https://stream01.example.com/control/drop/client?app=live&name=0'
```

Start or stop recording:

```sh
curl -u admin 'https://stream01.example.com/control/record/start?app=live&name=0'
curl -u admin 'https://stream01.example.com/control/record/stop?app=live&name=0'
```

Omitting `rec` targets the automatic `record all` recorder. `record/stop` closes the current file; recording resumes on the next publish or when `record_interval` triggers. Use `record/start` to restart it immediately. A named recorder with `record manual;` is only needed if you want independent manual recordings controlled with `rec=<name>`.

Redirect a publisher or its viewers to a new stream name:

```sh
curl -u admin 'https://stream01.example.com/control/redirect/publisher?app=live&name=0&newname=2'
curl -u admin 'https://stream01.example.com/control/redirect/subscriber?app=live&name=0&newname=2'
```

`redirect/publisher` renames the live stream, so its HLS URL and recording filename change. `redirect/subscriber` moves RTMP viewers only; HLS viewers are not RTMP subscriber sessions and must load the new URL themselves.

`drop` and `redirect` also accept optional `addr` and `clientid` filters to target one client.

Show RTMP statistics:

```sh
curl -u admin 'https://stream01.example.com/stat'
```

`curl -u admin` prompts for the password. Each vhost controls and reports only its own stream. The control path format is `/control/<section>/<method>?args`, not `/control?method=...`. `/stat` returns raw XML; the old `stat.xsl` stylesheet is not served.

If `CONTROL_USER` or `CONTROL_PASSWORD` is empty, `/control` returns `404` and `/stat` is reachable only from inside the container. Recreate the containers after changing credentials:

```sh
docker compose up -d --force-recreate
```

`docker inspect` exposes `CONTROL_PASSWORD`. To avoid that, set `CONTROL_PASSWORD_FILE` to a mounted file or Docker secret instead.

## HAProxy

HAProxy should terminate TLS on 443 and route by hostname to the matching loopback backend:

| Public hostname | Backend |
|---|---|
| `stream01.<domain>` | `127.0.0.1:18080` |
| `stream02.<domain>` | `127.0.0.1:18081` |
| `stream03.<domain>` | `127.0.0.1:18082` |
| `stream04.<domain>` | `127.0.0.1:18083` |
| `stream05.<domain>` | `127.0.0.1:18084` |
| `stream06.<domain>` | `127.0.0.1:18085` |
| `stream07.<domain>` | `127.0.0.1:18086` |
| `stream08.<domain>` | `127.0.0.1:18087` |
| `stream09.<domain>` | `127.0.0.1:18088` |

The backend uses plain HTTP. No certificate is needed inside the containers. Basic Auth is handled by nginx; HAProxy forwards the `Authorization` header by default, so no HAProxy userlist is required.

If HAProxy already has a `*:443` frontend, merge the certificates and `use_backend` rules into it instead of creating a second bind.

A complete example is in [`haproxy/streams.cfg.example`](haproxy/streams.cfg.example). It includes hostname routing, TLS certificates, and `/healthz` checks.

Use `/healthz` for backend health checks:

```text
GET /healthz
```

Do not use `/stat` for health checks; it requires Basic Auth when credentials are configured.

The player and HLS playlist are served by the same backend, so HAProxy only needs to forward the request. The player uses relative URLs and works unchanged behind HTTPS.

If HAProxy runs in a container instead of on the host, either:

- attach HAProxy to the `nginx-live-net` network and use `nginx-live-1:80` … `nginx-live-9:80`, or
- set `HTTP_BIND=0.0.0.0` in `.env` and point HAProxy at the host gateway.

## Recordings

All nine containers share the `nginx-live-recordings` volume. Each one writes only to its own directory, `/var/rec/stream-1` through `/var/rec/stream-9`. On startup the container creates that directory and gives `/var/rec` to the `nginx` user, including when an older volume was root-owned.

Current settings:

- `record all`
- `record_unique on`
- `record_interval 1h`
- `record_max_size 2048m` (2 GiB)
- After each recording segment closes, ffmpeg remuxes the FLV to MP4.

List recordings:

```sh
docker exec nginx-live-1 ls -lh /var/rec/stream-1
```

or:

```sh
docker run --rm -v nginx-live-recordings:/rec alpine ls -lhR /rec
```

Optional retention cleanup:

```sh
docker compose --profile cleanup up -d
```

This deletes files older than `RECORD_RETENTION_DAYS` every hour.

To remove the volume and all recordings:

```sh
docker compose down -v
```

## Security

This stage deliberately has no RTMP publish authentication and no TLS on RTMP.

- Anyone who can reach 1935–1943 can publish to that container's configured stream key. RTMP has no password.
- Any other stream key is refused, so a mismatched key does not create a second HLS playlist on that container.
- RTMP is plaintext.
- Restrict the RTMP ports with a firewall, VPN, or private bind address.
- HAProxy provides HTTPS for viewers and for `/control` and `/stat`.
- `/control` and `/stat` require Basic Auth when `CONTROL_USER` and `CONTROL_PASSWORD` are set.
- Without credentials, `/control` returns 404 and `/stat` is reachable only from inside the container.
- `/control` exposes `drop`, `record`, and `redirect`. These can disconnect clients, stop the current recording, or rename a live stream. Keep the password strong and use HTTPS.
- `/crossdomain.xml` and `/stat.xsl` are not served.
- Do not send Basic Auth over plain HTTP. Keep `HTTP_BIND=127.0.0.1` and publish only through HAProxy on 443.
- `docker inspect` exposes `CONTROL_PASSWORD`. Use `CONTROL_PASSWORD_FILE` with a mounted file or Docker secret if that matters.

Set `RTMP_BIND` to a private address if publishers are on a VPN:

```dotenv
RTMP_BIND=10.0.0.10
```

## Configuration

Edit `.env`:

```dotenv
# Current stage
RTMP_BIND=0.0.0.0
HTTP_BIND=127.0.0.1
RECORD_RETENTION_DAYS=14

# Basic Auth for /control and /stat. Leave the password empty to keep them disabled.
CONTROL_USER=admin
CONTROL_PASSWORD=
# CONTROL_PASSWORD_FILE=/run/secrets/control_password

# Future nginx-proxy stage; not used by this compose file
DOMAIN=example.com
LETSENCRYPT_EMAIL=admin@example.com
LETSENCRYPT_TEST=true
```

`.env` is ignored by git. Do not commit real credentials.

Changing `CONTROL_USER`, `CONTROL_PASSWORD`, or the contents of `CONTROL_PASSWORD_FILE` requires recreating the containers:

```sh
docker compose up -d --force-recreate
```

Each container reads its stream name from `config/stream-N.json`, mounted at `/www/stream.json`. Reload the page to change the title. The stream name is read when the container starts and is the only RTMP stream key that container accepts. `name` may contain letters, digits, `.`, `_`, and `-`. Recreate the containers after changing `name`:

```sh
docker compose up -d --force-recreate
```

The compose file also sets `VIRTUAL_HOST`, `VIRTUAL_PORT`, and `LETSENCRYPT_HOST` on every stream container. These are inert in this stage. They are kept for a future `nginx-proxy` + `acme-companion` deployment. If that proxy runs on a different Docker host, copy the same hostname mapping into that setup.

## Build details

- nginx **1.30.7**
- Alpine **3.24**
- nginx-rtmp-module **1.2.2**
- video.js **8.24.2**, vendored locally
- nginx and module source archives are SHA-256 verified in the Dockerfile

## Troubleshooting

**HLS returns 404**

The playlist only exists after a publisher connects with the stream key in that container's `config/stream-N.json`. A different key is refused and does not create a playlist. Publish first, then request `/live/<name>.m3u8`.

**`docker compose ps` shows a container restarting**

Check the logs:

```sh
docker compose logs --tail=100 nginx-live-1
```

**Port already in use**

Another service is using one of 1935–1943 or 18080–18088. Change the host port mapping or stop the conflicting service.

**Recordings are not writable**

Restart the stream containers. Startup creates `/var/rec/stream-N` and gives `/var/rec` to the `nginx` user. To discard the volume and start empty:

```sh
docker compose down -v
docker compose up -d
```

This deletes existing recordings.

**HAProxy returns 503**

Check the matching backend directly:

```sh
curl -v http://127.0.0.1:18080/healthz
```

If that fails, check the container health and logs.

**Video does not autoplay**

Browsers allow muted autoplay but may still block playback in some configurations. Press the play button.

**`/control` returns 404**

`CONTROL_USER` or `CONTROL_PASSWORD` is empty, or the containers have not been recreated after the `.env` change. Check the container environment:

```sh
docker compose exec nginx-live-1 env | grep CONTROL_
```

Then recreate the containers:

```sh
docker compose up -d --force-recreate
```

**`/control` or `/stat` returns 401**

Basic Auth is enabled. Use `curl -u admin ...` and enter the password, or use the browser password prompt. If the password was changed, recreate the containers.

**`/stat` returns 403**

The old localhost-only configuration is probably still running. Rebuild and recreate:

```sh
docker compose build
docker compose up -d --force-recreate
```
