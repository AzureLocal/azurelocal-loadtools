# Tool Comparison Matrix

![Category: Reference](https://img.shields.io/badge/Category-Reference-E67E22?style=flat-square)

This page provides a side-by-side comparison of all tools in the Azure Local Load Testing Framework. For selection guidance, see the [Tool Selection Guide](../architecture/tool-selection.md).

---

## Capability Matrix

| Dimension | fio | iPerf3 | HammerDB | stress-ng | VMFleet |
|-----------|:---:|:------:|:--------:|:---------:|:-------:|
| **Target OS — Linux** | ✅ | ✅ | — | ✅ | — |
| **Target OS — Windows** | — | ✅ | ✅ | — | ✅ |
| **Network testing** | — | ✅ | — | — | — |
| **Storage I/O testing** | ✅ | — | — | ✅ (VFS) | ✅ |
| **Database workload testing** | — | — | ✅ | — | — |
| **CPU stress testing** | — | — | — | ✅ | — |
| **Memory stress testing** | — | — | — | ✅ | — |
| **VM fleet workload simulation** | — | — | — | — | ✅ |
| **Install script included** | ✅ | — | ✅ | — | ✅ |
| **CI/CD pipeline included** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Ansible role included** | ✅ | — | — | — | — |

---

## Output and Metrics

| Tool | Output Format | Primary Metric | Secondary Metrics |
|------|--------------|---------------|------------------|
| fio | JSON | IOPS | Throughput MB/s, Latency P99 ms |
| iPerf3 | JSON | Throughput MB/s | Jitter ms, Retransmits, Packet loss % |
| HammerDB | Log → JSON | NOPM | TPM, Peak NOPM, Sample count |
| stress-ng | YAML → JSON | bogo-ops/sec | Total bogo-ops, Real time, Usr/sys time |
| VMFleet | CSV → JSON | Cluster IOPS | CPU %, Latency ms, Queue depth |

---

## Profile Summary

| Tool | Profile Count | Profile Files Location |
|------|:------------:|----------------------|
| fio | 5 | `config/profiles/fio/` |
| iPerf3 | 3 | `config/profiles/iperf/` |
| HammerDB | 2 | `config/profiles/hammerdb/` |
| stress-ng | 3 | `config/profiles/stress-ng/` |
| VMFleet | N/A | `config/` (config-driven, not profile-driven) |

---

## Monitoring Coverage

| Tool | Alert Rules | CPU Alerts | Memory Alerts | Storage Alerts | Network Alerts |
|------|:-----------:|:----------:|:-------------:|:--------------:|:--------------:|
| fio | 7 | ✅ | ✅ | ✅ | ✅ |
| iPerf3 | 6 | ✅ | ✅ | — | ✅ |
| HammerDB | 7 | ✅ | ✅ | ✅ | ✅ |
| stress-ng | 6 | ✅ | ✅ | ✅ | — |
| VMFleet | (shared PerfMon) | ✅ | ✅ | ✅ | ✅ |

---

## Connectivity Requirements

| Tool | Protocol | Port(s) | Auth Method |
|------|----------|---------|------------|
| fio | SSH | TCP 22 | Key-based (`linux_ssh`) |
| iPerf3 (server) | SSH | TCP 22 | Key-based (`linux_ssh`) |
| iPerf3 (test traffic) | TCP / UDP | TCP/UDP 5201 | None (direct) |
| HammerDB | WinRM / PowerShell remoting | TCP 5985 / 5986 | Windows credentials (`windows_winrm`) |
| stress-ng | SSH | TCP 22 | Key-based (`linux_ssh`) |
| VMFleet | WinRM / PowerShell remoting | TCP 5985 / 5986 | Windows credentials (`windows_winrm`) |

---

## Report Generation

All tools write an aggregate JSON file; there is no `New-LoadReport.ps1`. Each tool has an AsciiDoc template and cover page under `tools/<tool>/reports/templates/`. Only the VMFleet pipeline (`Invoke-VMFleetPipeline.ps1`, `-ReportFormats`) calls the report generator (`New-TestReport` in `common/modules/ReportGenerator`); `tools/vmfleet/scripts/New-VMFleetReport.ps1` writes an offline HTML and CSV report from one aggregate JSON.

| Tool | Template file | Cover page |
|------|--------------|-----------|
| fio | `tools/fio/reports/templates/report-template.adoc` | `cover-page.adoc` in the same folder |
| iPerf3 | `tools/iperf/reports/templates/report-template.adoc` | `cover-page.adoc` in the same folder |
| HammerDB | `tools/hammerdb/reports/templates/report-template.adoc` | `cover-page.adoc` in the same folder |
| stress-ng | `tools/stress-ng/reports/templates/report-template.adoc` | `cover-page.adoc` in the same folder |
| VMFleet | `tools/vmfleet/reports/templates/report-template.adoc` | `cover-page.adoc` in the same folder |

---

## When to Use Multiple Tools Together

See the [Tool Selection Guide — Combining Tools](../architecture/tool-selection.md#combining-tools) section for the recommended test sequence for production validation.
