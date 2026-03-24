# fio — Flexible I/O Tester

![Tool: fio](https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square)
![Status: Placeholder](https://img.shields.io/badge/Status-Placeholder-lightgrey?style=flat-square)

!!! caution
    **Placeholder** — Structure and Ansible roles scaffolded; implementation pending.

## Purpose

Fine-grained storage I/O benchmarking with extensive control over workload parameters. Runs inside Linux VMs on the cluster.

## When to Use

- Need precise control over I/O patterns beyond VMFleet's profiles
- Testing Linux VM storage performance specifically
- Validating I/O scheduler behavior, queue depths, or specific block sizes
- Client/server mode for distributed I/O testing

## Key Capabilities

- Job file-based workload definition
- Multiple I/O engines (libaio, io_uring, Windows IOCP)
- JSON output for automated parsing
- Verification mode for data integrity testing

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Linux VMs deployed on the Azure Local cluster
- Ansible 2.14+ for deployment (see [Ansible Requirements](../../getting-started/prerequisites.md#ansible-requirements-for-linux-based-tools))
- fio package installed on target VMs (automated via Ansible role)

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/fio/scripts/` |
| Ansible Playbooks | `tools/fio/playbooks/` |
| Job Files | `tools/fio/` |
| Profiles | `tools/fio/config/profiles/` |
| Ansible Role | `tools/fio/ansible/roles/fio/` |
