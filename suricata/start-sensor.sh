#!/usr/bin/env bash

set -uo pipefail

readonly SENSOR_IMAGE="jasonish/suricata:8.0"
readonly SENSOR_NAME="openhands-suricata"
readonly RULES_VOLUME="openhands-suricata-rules"
readonly PROXY_CONTAINER="openhands-proxy"
readonly READY_TIMEOUT_SECONDS=30

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$script_dir/logs"
local_rules="$script_dir/local.rules"
logrotate_script="$script_dir/logrotate.sh"

fail() {
  printf 'Suricata error: %s\n' "$*" >&2
  exit 1
}

command -v podman >/dev/null 2>&1 || fail "podman is not installed"
command -v sudo >/dev/null 2>&1 || fail "sudo is not installed"

mkdir -p "$log_dir"

printf 'Starting Suricata IDS (sudo is required for packet capture)...\n'
sudo -v || fail "sudo authentication failed"

if ! sudo podman volume exists "$RULES_VOLUME"; then
  sudo podman volume create "$RULES_VOLUME" >/dev/null || \
    fail "could not create the Suricata rules volume"
fi

if ! sudo podman run --rm \
  --volume "$RULES_VOLUME:/var/lib/suricata" \
  "$SENSOR_IMAGE" suricata-update --no-reload; then
  printf 'Warning: rule update failed; checking for cached rules.\n' >&2
  sudo podman run --rm \
    --volume "$RULES_VOLUME:/var/lib/suricata" \
    --entrypoint /usr/bin/test \
    "$SENSOR_IMAGE" \
    -s /var/lib/suricata/rules/suricata.rules || \
    fail "rule update failed and no cached rules are available"
fi

start_sensor_container() {
  local proxy_pid

  proxy_pid="$(podman inspect --format '{{if .State.Running}}{{.State.Pid}}{{end}}' "$PROXY_CONTAINER" 2>/dev/null)" || \
    return 1

  [[ "$proxy_pid" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -e "/proc/$proxy_pid/ns/net" ]] || return 1

  sudo podman run --detach --replace --rm \
    --name "$SENSOR_NAME" \
    --network "ns:/proc/$proxy_pid/ns/net" \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --cap-add SYS_NICE \
    --env "PUID=$(id -u)" \
    --env "PGID=$(id -g)" \
    --env ENABLE_CRON=yes \
    --volume "$RULES_VOLUME:/var/lib/suricata" \
    --volume "$log_dir:/var/log/suricata:z" \
    --volume "$local_rules:/opt/openhands/local.rules:ro,z" \
    --volume "$logrotate_script:/etc/cron.daily/suricata:ro,z" \
    "$SENSOR_IMAGE" \
    -i eth0 \
    -i eth1 \
    --set 'vars.address-groups.HOME_NET=[10.0.0.0/8]' \
    --init-errors-fatal \
    -s /opt/openhands/local.rules >/dev/null
}

sensor_started=false
for attempt in 1 2 3; do
  if start_sensor_container; then
    sensor_started=true
    break
  fi

  sleep 1
done

[[ "$sensor_started" == true ]] || fail "could not start Suricata in the proxy network namespace"

for ((attempt = 1; attempt <= READY_TIMEOUT_SECONDS; attempt++)); do
  if sudo podman logs "$SENSOR_NAME" 2>&1 | grep -qi 'engine started'; then
    printf 'Suricata IDS is monitoring the mitmproxy network namespace.\n'
    exit 0
  fi

  if ! sudo podman inspect --format '{{.State.Running}}' "$SENSOR_NAME" 2>/dev/null | grep -q true; then
    break
  fi

  sleep 1
done

printf 'Suricata did not become ready. Container output follows:\n' >&2
sudo podman logs "$SENSOR_NAME" >&2 2>&1 || true
sudo podman rm --force "$SENSOR_NAME" >/dev/null 2>&1 || true
fail "sensor startup failed"
