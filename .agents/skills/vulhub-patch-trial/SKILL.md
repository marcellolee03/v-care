---
name: vulhub-patch-trial
description: Run a supplied remediation script in a fresh Docker container for a data/vulhub case and record the user's scan result.
---

1. Create a fresh container from the case's `environment/docker-compose.yml` for each patch trial. Publish the case's ports on localhost by default. Stop prior trial containers to free the ports as needed. Remove them when requested.
2. Use `docker cp` to copy the chosen script from `patches/` byte for byte, then run it inside the container. Report its exit status and errors. A patch that requires editing to run is a failure. Use `docker restart` when changes need a restart to take effect. Leave remediation testing to the user's OpenVAS scan.
3. Update the case's `results.json` using script basenames without `.sh` as keys. Use `true` or `false` for confirmed outcomes and `null` for untested or pending results. Preserve other entries. Use the user's scan result even if the script exited nonzero.
