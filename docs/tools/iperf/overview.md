# iPerf3 — Network Performance Testing

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Status: Placeholder](https://img.shields.io/badge/Status-Placeholder-lightgrey?style=flat-square)

!!! caution
    **Placeholder** — Structure and Ansible roles scaffolded; implementation pending.

## Purpose

Network bandwidth, jitter, and packet loss measurement between cluster nodes and VMs.

## When to Use

- Validating RDMA/SMB Direct network paths between cluster nodes
- Measuring east-west bandwidth between VMs
- Testing Switch Embedded Teaming (SET) throughput
- Baseline network performance before deploying workloads

## Key Capabilities

- TCP, UDP, and SCTP protocol support
- Multi-stream parallel connections
- JSON output for automated parsing
- Server daemon mode for persistent testing endpoints

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- iPerf3 binaries on target nodes (Windows or Linux)
- RDMA configuration validated (for RDMA testing)
- Ansible 2.14+ for Linux VM deployment

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/iperf/scripts/` |
| Ansible Playbooks | `tools/iperf/playbooks/` |
| Profiles | `tools/iperf/config/profiles/` |
| Ansible Role | `tools/iperf/ansible/roles/iperf/` |
