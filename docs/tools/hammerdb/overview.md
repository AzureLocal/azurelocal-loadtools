# HammerDB — Database Benchmarking

![Tool: HammerDB](https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square)
![Status: Placeholder](https://img.shields.io/badge/Status-Placeholder-lightgrey?style=flat-square)

!!! caution
    **Placeholder** — Structure and Ansible roles scaffolded; implementation pending.

## Purpose

Database workload benchmarking for SQL Server running on Azure Local VMs.

## When to Use

- Validating SQL Server performance on the cluster
- OLTP (TPROC-C) workload benchmarking
- OLAP/analytics (TPROC-H) workload benchmarking
- Combined storage + compute performance validation

## Key Capabilities

- Supports SQL Server, PostgreSQL, MySQL, Oracle, and more
- TPC-C and TPC-H benchmark profiles
- GUI, CLI, and web interfaces
- Docker images for reproducible CI/CD runs

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- SQL Server instance deployed on an Azure Local VM
- HammerDB installed on the management station or target VM
- Ansible 2.14+ for automated deployment

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/hammerdb/scripts/` |
| Ansible Playbooks | `tools/hammerdb/playbooks/` |
| Profiles | `tools/hammerdb/config/profiles/` |
| Ansible Role | `tools/hammerdb/ansible/roles/hammerdb/` |
