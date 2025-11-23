#!/bin/bash
# Ultra-minimal no-op CNI plugin for gVisor
# Returns success without performing blocked networking operations

case "$CNI_COMMAND" in
    ADD)
        # Return minimal success response with IP assignment
        cat <<EOF
{
  "cniVersion": "1.0.0",
  "interfaces": [
    {
      "name": "eth0",
      "sandbox": "$CNI_NETNS"
    }
  ],
  "ips": [
    {
      "interface": 0,
      "address": "10.88.0.2/24"
    }
  ]
}
EOF
        ;;
    DEL)
        # No-op for deletion
        echo '{}'
        ;;
    CHECK)
        # Always return success
        echo '{}'
        ;;
    VERSION)
        cat <<EOF
{
  "cniVersion": "1.0.0",
  "supportedVersions": ["0.3.0", "0.3.1", "0.4.0", "1.0.0"]
}
EOF
        ;;
esac

exit 0
