# Introduction

![Category: Getting Started](https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square)

The Azure Local Load Testing Framework is a comprehensive, automated solution for load testing Azure Local (Azure Stack HCI) clusters. It validates storage, network, and compute performance before production or development workloads are migrated or deployed.

## Why Load Test Azure Local?

Azure Local clusters represent significant infrastructure investments. Before committing production workloads, organizations need confidence that:

- **Storage performance** meets application IOPS, throughput, and latency requirements
- **Network throughput** supports east-west traffic, RDMA/SMB Direct expectations
- **Compute capacity** handles expected virtual machine density
- **The cluster** operates stably under sustained load without thermal throttling or hardware degradation

## Supported Load Testing Tools

| Tool | Purpose | Status |
|------|---------|--------|
| [VMFleet](../tools/vmfleet/overview.md) | Storage load generation via VM fleet running DiskSpd workloads | ✅ Fully Implemented |
| [fio](../tools/fio/overview.md) | Fine-grained storage I/O benchmarking (Linux VMs) | ✅ Implemented |
| [iPerf3](../tools/iperf/overview.md) | Network bandwidth and latency testing | ✅ Implemented |
| [HammerDB](../tools/hammerdb/overview.md) | Database workload benchmarking (OLTP/OLAP) | ✅ Implemented |
| [stress-ng](../tools/stress-ng/overview.md) | CPU, memory, and system stress testing | ✅ Implemented |

## Key Features

- **100% Automated** — End-to-end pipeline from cluster validation to report generation
- **Configuration-Driven** — Master environment file with tagged variables; nothing hardcoded
- **Credential Security** — Azure Key Vault integration or interactive credential prompting
- **Comprehensive Monitoring** — Real-time storage, network, and compute metric collection
- **Multi-Format Reports** — PDF, Word (DOCX), and Excel (XLSX) output
- **CI/CD Ready** — GitHub Actions, Azure DevOps, and GitLab CI pipeline definitions
- **Modular Architecture** — Add new testing tools without modifying existing automation

## Project Repository

The source code is hosted at <https://github.com/AzureLocal/azurelocal-loadtools>.

## Next Steps

- [Prerequisites](prerequisites.md) — Ensure your environment is ready
- [Installation](installation.md) — Set up the framework
- [Configuration](configuration.md) — Configure your cluster and workloads
