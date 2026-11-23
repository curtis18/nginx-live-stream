# nginx-live-stream

Nine isolated nginx RTMP/HLS stream containers.

- RTMP ingest is direct on the host ports in `.env` (default **1935–1943**).
- Each container serves its own HTML5 player and HLS playlist over HTTP.
- HAProxy terminates TLS on **HTTPS_PORT** (default **443**) and forwards each public hostname to one container.
- The container HTTP ports in `.env` (default **18080–18088**) are bound to loopback and are only for HAProxy.
- Recordings are written to one shared Docker volume.
- The player page, `/control`, and `/stat` use env-driven Basic Auth when credentials are configured. HLS playlists and `/healthz` stay public.

## Architecture

```text
Viewer
  https://stream01.example.com/            ─┐
  https://stream01.example.com/live/0.m3u8 ─┼─> HAProxy :HTTPS_PORT
  https://stream01.example.com/healthz     ─┘        │
                                                     └─> http://127.0.0.1:18080 ─> nginx-live-1

Publisher
  rtmp://SERVER:1935/live/0 ─────────────────────────────> nginx-live-1  (direct)
```

`HTTPS_PORT` defaults to 443, so those viewer URLs have no port. Set `HTTPS_PORT=4447` and the same paths are `https://stream01.example.com:4447/`. The player, HLS media, `/stream.json`, `/healthz`, `/stat`, and `/control` all use that port. HAProxy owns the TLS certificates. The stream containers do not listen on `HTTPS_PORT`.

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

These are the defaults from `.env.example`. The backend range starts at 18080 instead of 8080 to avoid the common `127.0.0.1:8080` conflict. Change `RTMP_PORT_1`–`RTMP_PORT_9` or `HTTP_PORT_1`–`HTTP_PORT_9` in `.env` if the host differs, then recreate the containers.

The backend HTTP ports are not viewer URLs. Viewers use the HAProxy vhost. With the default `HTTPS_PORT=443`:

```text
https://stream01.example.com/
https://stream01.example.com/live/0.m3u8
https://stream01.example.com/healthz
```

When `HTTPS_PORT` is another port, include it: `https://stream01.example.com:4447/`.

## Requirements

- Docker Engine with Docker Compose v2.
- HAProxy on the same host, listening on `HTTPS_PORT` (443 by default).
- DNS records for the selected stream hostnames pointing at the HAProxy address. The default is nine.
- HAProxy certificates for those hostnames.

## Quick start

```sh
cp .env.example .env
# Edit .env and set CONTROL_PASSWORD before exposing the admin endpoints.
haproxy/render.sh
docker compose build
docker compose up -d
docker compose ps
```

If `CONTROL_USER` or `CONTROL_PASSWORD` is empty, the player page stays public, `/control` returns `404`, and `/stat` is reachable only from inside the container. Set a strong password before using the player or the admin endpoints.

Check a backend directly:

```sh
curl -fsS http://127.0.0.1:18080/healthz
```

Check through HAProxy after its configuration is updated:

```sh
curl -fsS https://stream01.example.com/healthz
```

When `HTTPS_PORT` is not 443, include that port, for example `curl -fsS https://stream01.example.com:4447/healthz`.

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

The player page, `/control`, and `/stat` are protected by Basic Auth when credentials are set. The containers generate the htpasswd file from `CONTROL_USER` and `CONTROL_PASSWORD` at startup, so no credentials are stored in the image and HAProxy does not need an auth userlist. HLS playlists, `/stream.json`, and `/healthz` stay public.

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

Show the RTMP statistics page:

```sh
curl -u admin 'https://stream01.example.com/stat'
```

`curl -u admin` prompts for the password. Each vhost controls and reports only its own stream. The control path format is `/control/<section>/<method>?args`, not `/control?method=...`. `/stat` returns the statistics page as HTML. The same password protects the player page.

If `CONTROL_USER` or `CONTROL_PASSWORD` is empty, the player page stays public, `/control` returns `404`, and `/stat` is reachable only from inside the container. Recreate the containers after changing credentials:

```sh
docker compose up -d --force-recreate
```

`docker inspect` exposes `CONTROL_PASSWORD`. To avoid that, set `CONTROL_PASSWORD_FILE` to a mounted file or Docker secret instead.

## HAProxy

HAProxy should terminate TLS on `HTTPS_PORT` and route by hostname to the matching loopback backend:

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

The table above is the default of nine streams (`HOST_PREFIX=stream`, `DOMAIN=example.com`, HTTP ports 18080–18088). `STREAM_COUNT` selects how many of those streams to run, from 1 to 9. `haproxy/render.sh --container 3` uses 3 for that run. Public names stay `${HOST_PREFIX}01.${DOMAIN}` onward. A production `.env` can set a different prefix and domain, for example `HOST_PREFIX=mcctv` and `DOMAIN=tdoffice.work`, without changing the repository.

The backend uses plain HTTP. No certificate is needed inside the containers. Basic Auth is handled by nginx; HAProxy forwards the `Authorization` header by default, so no HAProxy userlist is required.

When `HTTPS_PORT` is 443 and HAProxy already has a `*:443` frontend, merge the certificates and `use_backend` rules into that frontend instead of creating a second bind. When `HTTPS_PORT` is another port, add the rendered stream frontend on that port and leave the existing `*:443` frontend unchanged. Do not route the stream hostnames on 443 in that case.

[`haproxy/streams.cfg.template`](haproxy/streams.cfg.template) is the only HAProxy template. Render the local files from `.env`:

```sh
haproxy/render.sh
```

That writes `compose.yaml`, `haproxy/streams.cfg`, and `haproxy/certbot.sh` for `STREAM_COUNT` streams. Copy or merge `streams.cfg` into the server's HAProxy config, then reload HAProxy yourself. `render.sh` does not edit `/etc/haproxy/haproxy.cfg`, does not run certbot, and does not reload HAProxy.

```sh
haproxy/render.sh --container 3
docker compose up -d --remove-orphans
```

`--remove-orphans` stops containers that are no longer in the generated file. Lowering the count does not change an existing certificate until you review and run the new `haproxy/certbot.sh`.

Port 80 redirects to `HTTPS_PORT` except `/.well-known/acme-challenge/`, which is forwarded to `127.0.0.1:9080` (`ACME_PORT`). On a host where Certbot itself binds port 80, do not add that port 80 frontend. Review `haproxy/certbot.sh --help`, then run `sudo haproxy/certbot.sh` after the selected DNS names point at this host. `CERTBOT_EMAIL` is optional. When it is empty, the command uses `--register-unsafely-without-email` and leaves the Let's Encrypt account contact unset. Snap certbot's `snap.certbot.renew.timer` renews the certificate. The deploy hook installed by that command replaces the PEM and reloads HAProxy; the reload does not rewrite the HAProxy config. `.env`, `compose.yaml`, `haproxy/streams.cfg`, and `haproxy/certbot.sh` are not committed.

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
- HAProxy provides HTTPS for the player, `/control`, and `/stat`.
- The player page, `/control`, and `/stat` require Basic Auth when `CONTROL_USER` and `CONTROL_PASSWORD` are set. HLS media, `/stream.json`, and `/healthz` do not.
- Without credentials, the player page stays public, `/control` returns 404, and `/stat` is reachable only from inside the container.
- `/control` exposes `drop`, `record`, and `redirect`. These can disconnect clients, stop the current recording, or rename a live stream. Keep the password strong and use HTTPS.
- `/crossdomain.xml` is not served. The statistics stylesheet is applied on the server and is not a separate URL.
- Do not send Basic Auth over plain HTTP. Keep `HTTP_BIND=127.0.0.1` and publish only through HAProxy on `HTTPS_PORT`.
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

# Basic Auth for the player page, /control, and /stat. Leave the password empty to leave the player public.
CONTROL_USER=admin
CONTROL_PASSWORD=
# CONTROL_PASSWORD_FILE=/run/secrets/control_password

# Public names: stream01.example.com through stream09.example.com by default.
DOMAIN=example.com
HOST_PREFIX=stream
# 1 to 9. The default render is the first nine streams.
STREAM_COUNT=9
# Optional. Leave empty to keep the Let's Encrypt account contact unset.
CERTBOT_EMAIL=
ACME_PORT=9080
# Public TLS port. Use 4447 when 443 already serves other sites.
HTTPS_PORT=443

# Host ports. The container still listens on 1935 and 80.
RTMP_PORT_1=1935
HTTP_PORT_1=18080
```

`RTMP_PORT_2` through `RTMP_PORT_9` default to 1936–1943. `HTTP_PORT_2` through `HTTP_PORT_9` default to 18081–18088. The full list is in `.env.example`.

`.env` is ignored by git. Do not commit real credentials, `compose.yaml`, `haproxy/streams.cfg`, or `haproxy/certbot.sh`.

Changing the stream count, hostnames, ports, `CONTROL_USER`, `CONTROL_PASSWORD`, or the contents of `CONTROL_PASSWORD_FILE` requires rendering again and recreating the containers. After lowering `STREAM_COUNT`, `--remove-orphans` stops the extra containers:

```sh
haproxy/render.sh
docker compose up -d --force-recreate --remove-orphans
```

Reload HAProxy after a hostname, port, or count change. No image rebuild is required for those changes.

Each container reads its stream name from `config/stream-N.json`, mounted at `/www/stream.json`. The `name` field is the only RTMP key that container accepts. The defaults are `0`, `2`, `4`, `6`, `8`, `10`, `12`, `14`, and `16`. `name` may contain letters, digits, `.`, `_`, and `-`. Reload the page to change the title. Recreate that container after changing `name`:

```sh
docker compose up -d --force-recreate
```

Public hostnames come from `HOST_PREFIX` and `DOMAIN`. `haproxy/render.sh` writes them into `haproxy/streams.cfg`. The stream containers do not terminate TLS.

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

Another service is using one of the configured RTMP or HTTP ports (1935–1943 and 18080–18088 by default). Change `RTMP_PORT_*` or `HTTP_PORT_*` in `.env`, or stop the conflicting service. Recreate the containers after changing ports, and run `haproxy/render.sh` if an HTTP port changed.

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

Basic Auth is enabled. The player page returns 401 as well. Use `curl -u admin ...` and enter the password, or use the browser password prompt. If the password was changed, recreate the containers.

**`/stat` returns 403**

From outside the container, this is expected when `CONTROL_USER` or `CONTROL_PASSWORD` is empty. `/stat` is then limited to localhost. When credentials are set, rebuild and recreate so the running image includes the statistics page:

```sh
docker compose build
docker compose up -d --force-recreate
```
