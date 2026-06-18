#!/bin/sh

# Keep the documented first-login password from drifting to an empty root
# password on fresh images. Users should change it immediately after flashing.
ROOT_HASH='$6$znm2default$nwo/WFy57vlrCL6TiFnP2Oi8qXUY70Q7ZK6H3FXrvE.gNPHToM/8vtpUZSEDNUdHiJl/z3kQqVBLkAzIIFglM0'

if [ -f /etc/shadow ]; then
	sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" /etc/shadow
fi

exit 0
