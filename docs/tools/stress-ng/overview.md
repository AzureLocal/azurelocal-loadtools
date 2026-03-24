# stress-ng — System Stress Testing

![Tool: stress-ng](https://img.shields.io/badge/Tool-stress--ng-F39C12?style=flat-square)
![Status: Placeholder](https://img.shields.io/badge/Status-Placeholder-lightgrey?style=flat-square)

!!! caution
    **Placeholder** — Structure and Ansible roles scaffolded; implementation pending.

## Purpose

CPU, memory, cache, and system stress testing for capacity planning and burn-in validation.

## When to Use

- CPU stress testing for thermal and power validation
- Memory stress testing for stability under pressure
- Burn-in testing of new cluster nodes
- Capacity planning — determine maximum safe utilization levels

## Key Capabilities

- 370+ stress tests across CPU, memory, filesystem, network categories
- YAML job files for reproducible configurations
- Metrics: bogo ops/s, thermal zones, power measurement
- Stressor class system for targeted testing

## Prerequisites

In addition to the [common prerequisites](../../getting-started/prerequisites.md):

- Linux VMs deployed on the Azure Local cluster
- Ansible 2.14+ for deployment
- stress-ng package installed on target VMs (automated via Ansible role)

## File Locations

| Component | Path |
| --- | --- |
| Scripts | `tools/stress-ng/scripts/` |
| Ansible Playbooks | `tools/stress-ng/playbooks/` |
| Profiles | `tools/stress-ng/config/profiles/` |
| Ansible Role | `tools/stress-ng/ansible/roles/stress_ng/` |
