---
name: vulhub-patch-trial
description: Run an unmodified remediation script in a fresh Docker container for a data/vulhub case and record the execution failure or the user's scan result.
---

1. Create a fresh container from the case's `environment/docker-compose.yml` for each patch trial. Publish the case's ports on localhost by default. Stop prior trial containers to free the ports as needed. Remove them when requested.
2. Use `docker cp` to copy the chosen script from `patches/` byte for byte and run it once inside the container with its declared interpreter. Report its exit status and errors. Let the script handle its own dependencies and configuration. Do not edit the script, install prerequisites, change repositories or environment variables to help it run, or retry a failed run. If the script cannot start or exits nonzero, record the failure and end the trial. After a successful run, use `docker restart` when the patch needs a restart to take effect. Leave remediation testing to the user's OpenVAS scan.
3. Update the case's `results.json` using script basenames without `.sh` as keys and preserve other entries. Record `false` immediately for an execution failure. After a successful run, use `null` while the scan is pending, `true` if the user confirms remediation, and `false` if the user reports that the vulnerability remains. Use `null` for untested patches.
