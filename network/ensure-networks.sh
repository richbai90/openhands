#!/usr/bin/env bash

set -euo pipefail

ensure_internal_network() {
  local network_name="$1"
  local is_internal

  if ! podman network exists "$network_name"; then
    podman network create --internal "$network_name" >/dev/null
  fi

  is_internal="$(podman network inspect "$network_name" --format '{{.Internal}}')"
  if [[ "$is_internal" != "true" ]]; then
    printf 'Network %s exists but is not internal. Remove it and try again.\n' "$network_name" >&2
    return 1
  fi
}

ensure_internal_network openhands-agent-internal
ensure_internal_network openhands-observability-internal
