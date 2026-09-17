openhands () {
	local projects_dir="$HOME/code" 
	local current_dir="$PWD" 
	local container_workspace
	local stack_dir="$HOME/Dockerfiles/openhands" 
	local compose_file="$stack_dir/compose.yaml" 
	local network_script="$stack_dir/network/ensure-networks.sh" 
	local sensor_script="$stack_dir/suricata/start-sensor.sh" 
	local runtime_config_dir
	local trust=false 
	local force=false 
	local sensor_started=false 
	local openhands_status=1 
	local -a volume_args
	local -a openhands_args
	local arg
	for arg in "$@"
	do
		case "$arg" in
			(--trust) trust=true  ;;
			(--force) force=true  ;;
			(*) openhands_args+=("$arg")  ;;
		esac
	done
	if [[ "$current_dir" == "$projects_dir" || "$current_dir" == "$projects_dir/"* ]]
	then
		container_workspace="/workspace" 
		volume_args=(-v "$current_dir:/workspace:z") 
	elif [[ "$trust" == true ]]
	then
		container_workspace="/workspace" 
		volume_args=(-v "$current_dir:/workspace:z") 
	else
		echo "Refusing to mount a directory outside $projects_dir without --trust." >&2
		return 1
	fi
	command -v jq > /dev/null 2>&1 || {
		echo "OpenHands launcher requires jq to sanitize its runtime configuration." >&2
		return 1
	}
	runtime_config_dir="$(mktemp -d "${TMPDIR:-/tmp}/openhands-config.XXXXXXXX")"  || return 1
	jq '
    .llm.api_key = "proxy-managed" |
    .llm.base_url = "https://openrouter.ai/api/v1" |
    .condenser.llm.api_key = "proxy-managed" |
    .condenser.llm.base_url = "https://openrouter.ai/api/v1"
  ' "$HOME/.openhands/agent_settings.json" > "$runtime_config_dir/agent_settings.json" || {
		safe-rm -rf "$runtime_config_dir"
		return 1
	}
	if [[ -f "$HOME/.openhands/cli_config.json" ]]
	then
		cp "$HOME/.openhands/cli_config.json" "$runtime_config_dir/cli_config.json" || {
			safe-rm -rf "$runtime_config_dir"
			return 1
		}
	fi
	chmod 700 "$runtime_config_dir"
	chmod 600 "$runtime_config_dir"/*.json
	"$network_script" || {
		safe-rm -rf "$runtime_config_dir"
		return 1
	}
	OPENHANDS_RUNTIME_CONFIG="$runtime_config_dir" podman compose -f "$compose_file" up -d --build --force-recreate proxy || {
		safe-rm -rf "$runtime_config_dir"
		return 1
	}
	if "$sensor_script"
	then
		sensor_started=true 
	else
		if [[ "$force" != true ]]
		then
			echo "OpenHands was not started because Suricata is unavailable." >&2
			echo "Run with --force to explicitly start an unmonitored session." >&2
			safe-rm -rf "$runtime_config_dir"
			return 1
		fi
		echo "WARNING: Starting OpenHands without Suricata monitoring (--force)." >&2
	fi
	OPENHANDS_RUNTIME_CONFIG="$runtime_config_dir" podman compose -f "$compose_file" up -d evebox || echo "Warning: EveBox failed to start; Suricata logs remain available on disk." >&2
	{
		OPENHANDS_WORK_DIR="$container_workspace" OPENHANDS_RUNTIME_CONFIG="$runtime_config_dir" podman compose -f "$compose_file" run --rm --no-deps "${volume_args[@]}" openhands "${openhands_args[@]}"
		openhands_status=$? 
	} always {
		if [[ "$sensor_started" == true ]]
		then
			echo "Stopping Suricata IDS..."
			sudo podman stop --ignore --time 10 openhands-suricata > /dev/null || echo "Warning: Suricata could not be stopped automatically." >&2
		fi
		safe-rm -rf "$runtime_config_dir"
	}
	return "$openhands_status"
}
