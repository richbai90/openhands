#!/bin/sh

set -eu

cp /run/openhands-config/agent_settings.json /root/.openhands/agent_settings.json
if [ -f /run/openhands-config/cli_config.json ]; then
    cp /run/openhands-config/cli_config.json /root/.openhands/cli_config.json
fi

exec openhands "$@"
