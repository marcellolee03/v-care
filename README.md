# v-care

## Haiku patch trial notes

Record the script exit code alongside the OpenVAS outcome. Two of the four recorded Haiku trials passed the scan after exiting with code `1`.

| Trial | Exit code | OpenVAS outcome | Execution detail |
| --- | --- | --- | --- |
| ActiveMQ default credentials | `1` | Pass | The final sanity check failed after the password entries were replaced. |
| Adminer OS end-of-life detection | `1` | Pass | APT failed on missing Bookworm signing keys before any packages were upgraded. |
| ActiveMQ cleartext transmission | `1` | Fail | The script aborted before replacing `jetty.xml`. |
| Adminer 4.8.1 DoS | `127` | Pass | Bash interpreted Markdown fences as command substitution and tried to execute the script's log output. |

An OpenVAS pass means the finding cleared in that scan. The Adminer end-of-life trial still needs evidence of an OS upgrade before it can establish that the OS issue was remediated.
