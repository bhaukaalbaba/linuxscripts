# ipembed

Deterministic IPv4 ↔ IPv6 embedding tool for ISP and NOC environments.

`ipembed` converts IPv4 addresses into IPv6 addresses by embedding the IPv4 value into the lower 32 bits of an IPv6 `/64` prefix. It also performs reverse extraction, batch processing, CSV/JSON export, reverse DNS generation, and strict RFC validation.

---

## Why This Exists

When running dual-stack inside an ISP or large internal network, engineers often want:

- IPv4 and IPv6 to be visually correlated
- Deterministic mapping without IPAM lookup
- Simple troubleshooting
- Automation-friendly behavior

Instead of random IPv6 host bits, `ipembed` embeds the IPv4 address directly into the last 32 bits of IPv6.

### Example

```text
IPv4:   172.28.134.172
Prefix: 2001:db8:cafe:100::/64

Result:
2001:db8:cafe:100::ac1c:86ac
```

---

## Standards

The approach aligns with:

- RFC 4291 – IPv6 Addressing Architecture
- RFC 6052 – IPv4/IPv6 Translation Address Format

This tool uses a deterministic `/96-style IPv4 embedding` model for infrastructure use.

---

# Features

- IPv4 → IPv6 conversion
- IPv6 → IPv4 extraction
- Strict RFC validation
- Custom `/64` prefix support
- IPv6 compressed/expanded normalization
- Batch mode (100k+ records optimized)
- CSV export
- Optional JSON output
- Reverse DNS helper
- CI-friendly exit codes
- Failure logging
- Zero Python dependency (pure Bash)

---

# Installation

```bash
git clone https://github.com/bhaukaalbaba/linuxscripts.git
cd ipembed
chmod +x ipembed
```

Optional:

```bash
sudo mv ipembed /usr/local/bin/
```

---

# Usage

## IPv4 → IPv6

```bash
ipembed -4 192.168.10.5 --prefix 2001:db8:cafe:200::/64
```

Output:

```text
2001:db8:cafe:200::c0a8:a05
```

---

## IPv6 → IPv4

```bash
ipembed -6 2001:db8:cafe:200::c0a8:a05
```

Output:

```text
192.168.10.5
```

---

## Batch Mode

Example input file:

```text
# Server list
10.0.0.1
192.168.1.1

bad.ip
```

Run:

```bash
ipembed -b input.txt --prefix 2001:db8:cafe:300::/64
```

Using stdin:

```bash
cat input.txt | ipembed -b -
```

---

## CSV Output

```bash
ipembed -b input.txt --prefix 2001:db8:cafe:300::/64 --csv
```

Output:

```csv
input,output,status
10.0.0.1,2001:db8:cafe:300::a00:1,OK
192.168.1.1,2001:db8:cafe:300::c0a8:101,OK
bad.ip,,ERROR
```

---

## JSON Output (Optional)

Single:

```bash
ipembed -4 10.0.0.1 --prefix 2001:db8:cafe:1::/64 --json
```

Output:

```json
{
  "input": "10.0.0.1",
  "output": "2001:db8:cafe:1::a00:1",
  "status": "OK"
}
```

Batch:

```bash
ipembed -b input.txt --prefix 2001:db8:cafe:1::/64 --json
```

Outputs a JSON array.

---

## Reverse DNS Helper

IPv4:

```bash
ipembed -r 172.16.10.5
```

Output:

```text
5.10.16.172.in-addr.arpa
```

IPv6:

```bash
ipembed -r 2001:db8:cafe::a00:101
```

Output:

```text
...ip6.arpa
```

---

# Exit Codes

Designed for CI/CD environments.

| Code | Meaning |
|------|----------|
| 0 | Success |
| 1 | Invalid input |
| 2 | Invalid prefix |
| 3 | Batch failures occurred |
| 4 | Internal error |
| 5 | Invalid arguments |

Example CI usage:

```bash
ipembed -b servers.txt --prefix 2001:db8:cafe:1::/64 || exit 1
```

---

# Performance

Optimized for large-scale batch processing.

| Records | Approx Time |
|----------|------------|
| 10,000   | < 0.5s |
| 100,000  | ~3–4s |
| 1,000,000 | ~40s |

Pure Bash arithmetic. No Python. No external libraries.

---

# Validation & Strict Mode

The tool performs:

- Strict IPv4 octet validation (0–255)
- Strict IPv6 hex validation
- Compressed → expanded normalization
- Lower 32-bit extraction only
- Mandatory `/64` prefix for embedding

---

# Design Philosophy

Intended for infrastructure addressing only, not:

- SLAAC client addressing
- Public exposure
- Randomized host addressing

Recommended for:

- Servers
- Network infrastructure
- Internal services
- Deterministic addressing policies

---

# Logging

Batch failures are logged to:

```text
./ipembed_failures.log
```

---

# Example Real-World Usage (ISP)

```text
Core:      2001:db8:cafe:100::/64
Servers:   2001:db8:cafe:200::/64
Storage:   2001:db8:cafe:300::/64

IPv4: 172.28.134.172
IPv6: 2001:db8:cafe:200::ac1c:86ac
```

Engineers can derive IPv4 instantly from IPv6.

---

# Contributing

Pull requests welcome.

Please ensure:

- Strict validation remains intact
- No heavy external dependencies
- CI exit codes preserved

---

# License

Internal infrastructure utility.  
Adapt and use freely in operational environments.
