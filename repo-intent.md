# Repo intent — azurelocal-loadtools

**Load testing and benchmarking framework for Azure Local.**

## What this repo is

Automated performance and load testing for Azure Local clusters — storage,
network, database, and system stress — with standardised reporting, using FIO,
HammerDB, iPerf, stress-ng, and VMFleet.

> **Under active development.** Scripts, templates, and automation are not
> guaranteed to work at this time.

## Shape

- `config/` — central variable reference (`variables.example.yml`)
- `src/` — shared modules and helpers
- `tools/vmfleet/` — storage IOPS/throughput/latency (DiskSpd)
- `tools/fio/` — fine-grained storage I/O benchmarking
- `tools/iperf/` — network bandwidth, jitter, packet loss
- `tools/hammerdb/` — database benchmarking

## How it relates to other repos

- Part of the AzureLocal toolkit family; docs at azurelocal.cloud

## Status

Active, early — explicitly "use at your own risk, expect breaking changes."
