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

All tools write an aggregate JSON file consumed by `New-LoadReport.ps1`. The report template and placeholder mapping differ by tool:

| Tool | Template File | Key Placeholders |
|------|--------------|-----------------|
| fio | `reports/templates/fio-report.adoc` | `{seq_read_iops}`, `{rand_write_iops}`, `{p99_latency_ms}` |
| iPerf3 | `reports/templates/iperf-report.adoc` | `{tcp_avg_throughput_mbps}`, `{udp_avg_jitter_ms}` |
| HammerDB | `reports/templates/hammerdb-report.adoc` | `{peak_nopm}`, `{avg_nopm}`, `{peak_tpm}` |
| stress-ng | `reports/templates/stress-ng-report.adoc` | `{cpu_avg_bogo_ops_per_sec}`, `{memory_avg_bogo_ops_per_sec}` |
| VMFleet | `reports/templates/vmfleet-report.adoc` | `{cluster_iops}`, `{avg_latency_ms}` |

---

## When to Use Multiple Tools Together

See the [Tool Selection Guide — Combining Tools](../architecture/tool-selection.md#combining-tools) section for the recommended test sequence for production validation.
