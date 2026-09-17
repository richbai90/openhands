# OpenHands with mitmproxy and Suricata

This stack runs OpenHands inside its own Podman container, routes its HTTP and HTTPS traffic through mitmproxy, and monitors the proxy's network namespace with Suricata. EveBox provides a local dashboard for Suricata events.

## Start OpenHands

Reload the shell function after changing it:

```sh
source ~/.config/zsh/sourcefiles/01-functions.zsh
```

Then launch OpenHands normally:

```sh
openhands
```

The launcher starts mitmproxy, asks for `sudo` to start the rootful Suricata sensor, starts EveBox, and then opens the OpenHands TUI. Suricata needs root privileges for live packet capture; the other containers remain rootless.

OpenHands is attached only to an internal Podman network, so removing its proxy environment variables does not create a direct Internet route. Mitmproxy spans that internal network and a separate egress network. EveBox is isolated on a third network. The launcher creates and verifies the internal networks outside Compose because `podman-compose` 1.6.0 accepts `internal: true` but creates an externally routed network.

The launcher accepts two wrapper flags in any order:

- The current directory is the only workspace mounted into the container.
- `--trust` permits that mount when the current directory is outside `~/code`; without it, the launcher refuses to start.
- `--force` starts OpenHands when Suricata cannot start. This produces an explicit warning and leaves the session unmonitored.

Any other arguments are forwarded to OpenHands:

```sh
openhands --trust --force --resume --last
```

## Customize mitmproxy

The mitmproxy image has its own build context in `proxy/`. Edit `proxy/inspect.py`, then rebuild it with:

```sh
podman compose -f ~/Dockerfiles/openhands/compose.yaml build --no-cache proxy
```

The next `openhands` launch recreates the proxy container from that image. The launcher also uses `--build`, so normal launches automatically pick up newer files without requiring a manual rebuild.

The host's `~/.openhands` directory is never mounted into OpenHands. The launcher preserves the essential settings in a temporary copy, replaces API keys with a non-secret placeholder, and pins the OpenRouter endpoint. The container copies those settings into tmpfs at startup, while mitmproxy injects the real OpenRouter credential into outbound requests.

Auto-loaded skills are mounted read-only, and conversations use a Podman-managed volume rather than host configuration storage. Changes to settings, cache data, or skills inside a session cannot modify the host copies or survive container teardown. Rotate any API key that was visible to a previous sandbox.

## Dashboards and logs

- mitmproxy: <http://127.0.0.1:8081> (password: `secret`)
- EveBox: <http://127.0.0.1:5636>
- Suricata alerts: `suricata/logs/fast.log`
- Structured events: `suricata/logs/eve.json`
- Sensor diagnostics: `suricata/logs/suricata.log`

Useful commands:

```sh
tail -f ~/Dockerfiles/openhands/suricata/logs/fast.log
jq -c 'select(.event_type == "alert")' ~/Dockerfiles/openhands/suricata/logs/eve.json
sudo podman logs openhands-suricata
```

EveBox uses a local SQLite database with its default seven-day event retention. Its port is bound only to localhost, so authentication and TLS are disabled.

## Verify detection

From an OpenHands session, run this plain HTTP request:

```sh
curl --proxy http://openhands-proxy:8080 \
  -H 'X-Suricata-Test: openhands-suricata-test' \
  http://example.com/
```

The request should create an `OPENHANDS IDS validation request` alert in `fast.log`, `eve.json`, and EveBox. Two alerts are normal because Suricata sees both the OpenHands-to-proxy and proxy-to-server legs. The validation rule is in `suricata/local.rules`.

## Rules and lifecycle

The launcher updates the Emerging Threats Open ruleset before starting the sensor. If updating fails but cached rules exist, it uses the cached rules. If no usable rules or sensor are available, OpenHands aborts unless `--force` was supplied.

The sensor runs only while the OpenHands command is active. The launcher stops it on normal exit, errors, or `Ctrl+C`; Podman's `--rm` then removes the sensor container. The rootful rules volume remains so later launches can reuse downloaded rules, while EveBox remains available for reviewing historical events.

If a terminal or host failure leaves the sensor behind, stop it manually. Stop the rootless services separately when you no longer need their dashboards:

```sh
sudo podman stop openhands-suricata
podman compose -f ~/Dockerfiles/openhands/compose.yaml down
```

## Visibility limits

Suricata sees network flows, IP addresses, DNS, TLS metadata, protocol anomalies, plaintext HTTP, and signature matches. It does not see decrypted HTTPS request or response bodies: mitmproxy decrypts HTTPS internally and re-encrypts both sides of the connection. Use the mitmproxy dashboard when you need decrypted HTTP details.
