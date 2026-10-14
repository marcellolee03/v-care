# Vulnerability Reader

This module reads the vulnerability folders in `data/` and generates JSONL
records for other scripts or models to consume.

Each vulnerability directory must contain:

```text
data/<vulnerability-name>/
  environment_info.txt
  report.csv                 # 3 reports missing : coldfusion,fckeditor and mysql authentic bypass
  patches/
    <model>_patch.sh
    <model>_details.txt
```

Directories without `patches/` are ignored automatically.

## Run

From the project root, use `uv`:

```powershell
uv run python src/v_care/reader/run.py
```

With no arguments, the command reads every vulnerability and writes one JSON
record per vulnerability to:

```text
output/vulnerabilities.jsonl
```

To select specific directories:

```powershell
uv run python src/v_care/reader/run.py activemq jenkins-arbitrary-file-read
```

The result is saved to:

```text
output/selected-vulnerabilities.jsonl
```

To write JSONL directly to the terminal:

```powershell
uv run python src/v_care/reader/run.py activemq --stdout
```

## JSONL format

Each line is a complete, independent JSON object:

```json
{
  "name": "example-vulnerability",
  "nvt_oid": "1.3.6.1.4.1.25623.1.0.123456",
  "environment_info": {
    "os_info": {
      "pretty_name": "Debian GNU/Linux 12 (bookworm)",
      "name": "Debian GNU/Linux",
      "version_id": "12",
      "version": "12 (bookworm)",
      "version_codename": "bookworm",
      "id": "debian",
      "home_url": "https://www.debian.org/",
      "support_url": "https://www.debian.org/support",
      "bug_report_url": "https://bugs.debian.org/"
    },
    "user_info": {
      "uid": 0,
      "username": "root",
      "gid": 0,
      "group": "root",
      "groups": [
        {
          "gid": 0,
          "name": "root"
        }
      ]
    },
    "package_manager": "/usr/bin/apt-get",
    "tools": [
      "/usr/bin/curl",
      "/usr/bin/wget",
      "/bin/sed",
      "/usr/bin/awk"
    ]
  },
  "report": {
    "IP": "192.0.2.10",
    "Hostname": "example-host",
    "Port": "8080",
    "Port Protocol": "tcp",
    "CVSS": "9.8",
    "Severity": "Critical",
    "QoD": "98",
    "Solution Type": "VendorFix",
    "NVT Name": "Example Service Remote Code Execution Vulnerability",
    "Summary": "The service is vulnerable to remote code execution.",
    "Specific Result": "Installed version: 1.0.0",
    "NVT OID": "1.3.6.1.4.1.25623.1.0.123456",
    "CVEs": "CVE-2026-12345",
    "Task ID": "11111111-1111-1111-1111-111111111111",
    "Task Name": "self-scan",
    "Timestamp": "2026-10-09T12:00:00Z",
    "Result ID": "22222222-2222-2222-2222-222222222222",
    "Impact": "An unauthenticated attacker may execute arbitrary commands.",
    "Solution": "Upgrade the service to version 1.0.1 or later.",
    "Affected Software/OS": "Example Service 1.0.0",
    "Vulnerability Insight": "The affected endpoint does not validate user input.",
    "Vulnerability Detection Method": "The vulnerable version was identified remotely.",
    "Product Detection Result": "Example Service 1.0.0 was detected on port 8080.",
    "BIDs": "",
    "CERTs": "",
    "Other References": "https://example.com/security/advisory"
  },
  "patches": [
    {
      "model": "example-model",
      "patch": "#!/bin/bash\nset -euo pipefail\napt-get update\napt-get install --only-upgrade example-service\n",
      "details": {
        "nvt_oid": "1.3.6.1.4.1.25623.1.0.123456",
        "vulnerability": "Example Service Remote Code Execution Vulnerability",
        "time_elapsed_seconds": 12.5,
        "functional": null
      }
    }
  ]
}
```

The example is indented only to make the structure easier to read. In the
generated JSONL file, each complete vulnerability object occupies a single
physical line. The example uses fictional values but includes every field
produced for this record shape.

`report` contains only the CSV row whose `NVT OID` matches the vulnerability.
The reader raises an error instead of silently selecting a row when the match
is missing or ambiguous. `report` is `null` when the directory does not contain
`report.csv`.

Environment and patch details are converted to structured values. Unknown
fields or sections are preserved in `extra`, `extra_sections`, or
`unparsed_lines` rather than being discarded.

## Python usage

```python
from v_care.reader import load_vulnerabilities

all_records = load_vulnerabilities()
selected_records = load_vulnerabilities(["activemq", "jenkins-arbitrary-file-read"])
```
