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
  "name": "activemq",
  "nvt_oid": "1.3.6.1.4.1.25623.1.0.108253",
  "environment_info": {
    "os_info": {"pretty_name": "Debian GNU/Linux 9 (stretch)"},
    "user_info": {"uid": 0, "username": "root"},
    "package_manager": "/usr/bin/apt-get",
    "tools": ["/usr/bin/curl", "/bin/sed"]
  },
  "report": {"NVT OID": "..."},
  "patches": [
    {
      "model": "deepseek-V3.1",
      "patch": "...",
      "details": {
        "nvt_oid": "...",
        "vulnerability": "...",
        "time_elapsed_seconds": 15.6407,
        "functional": null
      }
    }
  ]
}
```

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
