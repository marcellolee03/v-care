# Vulnerability Reader

This module reads the vulnerability folders in `data/` and generates JSONL
records for other scripts or models to consume.

Each vulnerability directory requires `report.csv` and can include these additional files:

```text
data/<source>/<vulnerability-name>/
  environment_info.json      # Structured environment context
  environment/               # Docker Compose / Dockerfile context (for Vulhub targets)
  report.csv                 # Single-row OpenVAS vulnerability report
```

- The parent directory supplies the `source` field. Its value is `web`, `vulhub`, or `pop_vm`.
- Directories without `report.csv` are skipped.

## Run

From the project root, use `uv`:

```powershell
uv run python src/v_care/reader/run.py
```

With no arguments, the command reads all **182 vulnerabilities** (55 `vulhub`, 16 `pop_vm`, and 111 `web`) and writes one JSON record per vulnerability to:

```text
output/vulnerabilities.jsonl
```

To select specific directories:

```powershell
uv run python src/v_care/reader/run.py vulhub/activemq pop_vm/jenkins-arbitrary-file-read web/cve-2021-26690
```

The result is saved to:

```text
output/selected-vulnerabilities.jsonl
```

To write JSONL directly to the terminal:

```powershell
uv run python src/v_care/reader/run.py activemq --stdout
```

### Filtering Flags

You can filter vulnerability records based on their metadata:

- **Filter by environment info:**
  ```powershell
  uv run python src/v_care/reader/run.py --with-env     # Vulnerabilities with environment info
  uv run python src/v_care/reader/run.py --without-env  # Vulnerabilities without environment_info
  ```

- **Filter by NVT OID type:**
  ```powershell
  uv run python src/v_care/reader/run.py --with-oid     # Vulnerabilities with standard OpenVAS OID (1.3.6.1...)
  uv run python src/v_care/reader/run.py --without-oid  # Vulnerabilities without a standard OID
  ```

- **Filter by CVE presence:**
  ```powershell
  uv run python src/v_care/reader/run.py --with-cve     # Vulnerabilities with associated CVE
  uv run python src/v_care/reader/run.py --without-cve  # Vulnerabilities without a CVE
  ```

- **Exclude `web` records:**
  ```powershell
  uv run python src/v_care/reader/run.py --exclude-new-batch
  ```

## JSONL format

Each line is a complete, independent JSON object:

```json
{
  "name": "example-vulnerability",
  "source": "vulhub",
  "nvt_oid": "1.3.6.1.4.1.25623.1.0.123456",
  "environment_details": {
    "service": {
      "port_internal": 8161,
      "protocol": "tcp",
      "application": "activemq",
      "version": "5.11.1",
      "install_method": "tarball",
      "install_root": "/opt/activemq",
      "config_paths": ["/opt/activemq/conf"]
    },
    "os": {
      "distro": "debian",
      "release": "9",
      "package_manager": "apt",
      "repos_reachable": true,
      "tools": ["apt", "apt-get", "awk", "bash", "curl", "grep", "sed", "tar"]
    },
    "filesystem": {
      "exec_user": "root",
      "writable": ["/dev/shm", "/etc", "/opt/activemq", "/tmp"],
      "mounts": [],
      "volatile_paths": ["/dev/shm", "/run", "/tmp"],
      "capabilities": ["default"],
      "init_system": false,
      "read_only_rootfs": false
    },
    "config_lifecycle": {
      "applies_on_restart": true,
      "main_pid_is_1": false
    }
  },
  "vulnerability_details": {
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
  }
}
```

The example is indented only to make the structure easier to read. In the
generated JSONL file, each complete vulnerability object occupies a single
physical line. The example uses fictional values but includes every field
produced for this record shape.

`vulnerability_details` contains the first CSV row. The reader uses that row's `NVT OID`
and raises an error if it cannot find one.

Environment info is loaded from each vulnerability directory. Missing or
unreadable `environment_info.json` produces `"environment_details": null`.

## Python usage

```python
from v_care.reader import load_vulnerabilities

# Load all records
all_records = load_vulnerabilities()

# Load specific folders by name
selected_records = load_vulnerabilities(["activemq", "cve-2021-26690"])

# Filter by metadata flags
only_with_env = load_vulnerabilities(has_env=True)        # Records with environment info
only_without_env = load_vulnerabilities(has_env=False)    # Records without environment info
only_standard_oid = load_vulnerabilities(has_oid=True)    # Records with 1.3.6.1... OID
cve_based_only = load_vulnerabilities(has_oid=False)      # Records without a standard OID
without_cve = load_vulnerabilities(has_cve=False)         # Records without a CVE
```
