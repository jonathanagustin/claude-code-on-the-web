#!/bin/bash

# runc wrapper for gVisor compatibility
# Removes cgroup namespace from OCI spec before execution
# gVisor kernel doesn't support cgroup namespaces

RUNC_REAL="/usr/bin/runc.real"

# Function to strip cgroup namespace from config.json
strip_cgroup_namespace() {
    local config_file="$1"

    if [ -f "$config_file" ]; then
        # Use jq to remove cgroup namespace if available
        if command -v jq &> /dev/null; then
            jq 'del(.linux.namespaces[] | select(.type == "cgroup"))' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        else
            # Fallback: use sed to remove cgroup namespace
            sed -i '/{"type":"cgroup"}/d' "$config_file"
            sed -i '/"type": "cgroup"/d' "$config_file"
        fi
    fi
}

# Check if this is a 'run' or 'create' command that needs spec modification
if [ "$1" = "run" ] || [ "$1" = "create" ]; then
    # Find the bundle directory (contains config.json)
    BUNDLE_DIR=""

    # Parse arguments to find --bundle flag or default to current directory
    for ((i=1; i<=$#; i++)); do
        if [ "${!i}" = "--bundle" ] || [ "${!i}" = "-b" ]; then
            j=$((i+1))
            BUNDLE_DIR="${!j}"
            break
        fi
    done

    # Default to current directory if no bundle specified
    if [ -z "$BUNDLE_DIR" ]; then
        BUNDLE_DIR="."
    fi

    # Strip cgroup namespace from config
    strip_cgroup_namespace "$BUNDLE_DIR/config.json"
fi

# Apply LD_PRELOAD for /proc/sys/* redirection if library exists
if [ -f /tmp/runc-preload.so ]; then
    export LD_PRELOAD=/tmp/runc-preload.so
fi

# Execute real runc with all arguments
exec "$RUNC_REAL" "$@"
