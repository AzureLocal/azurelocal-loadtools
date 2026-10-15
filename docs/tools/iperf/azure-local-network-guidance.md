# Azure Local Network Guidance for iPerf3

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-0078D4?style=flat-square)

iPerf3 measures TCP and UDP between two endpoints. On Azure Local that is useful for some paths and blind to others. Read this before you trust a green result.

## iPerf3 does not exercise RDMA

Storage traffic between Azure Local machines uses SMB Direct over RDMA on the storage adapter ports. Learn describes RDMA as "a network stack offload to the network adapter" that "allows SMB storage traffic to bypass the operating system for processing" ([Host network requirements for Azure Local](https://learn.microsoft.com/azure/azure-local/concepts/host-network-requirements)). iPerf3 sends ordinary TCP or UDP through the Windows or Linux network stack. It never opens an RDMA connection.

So a clean iPerf3 run on the storage network proves that the IP path, VLAN, MTU and TCP throughput work. It does **not** prove that:

- RDMA is enabled and in use on the adapters;
- Data Center Bridging, Priority Flow Control and ETS are correct across every port and switch (required for RoCE, optional for iWARP);
- SMB Multichannel and SMB Direct fail over when a path is lost.

A cluster can pass iPerf3 at line rate and still run storage over TCP, or stall under load because PFC is wrong.

## Where iPerf3 is the right tool

| Path | Use iPerf3? |
|------|-------------|
| Management and compute network between machines, VMs, and external endpoints | Yes |
| VM to VM and VM to external bandwidth, jitter and loss (UDP profile) | Yes |
| Storage (SMB Direct / RDMA) between machines | **No**: use the checks below |
| Live migration | Partly: the transport and bandwidth limits differ from a plain TCP stream |

## How to validate RDMA and storage networking instead

The Learn pages below are the documented route. This repository does not automate them.

1. Confirm the adapters are RDMA capable and enabled (`Get-SmbServerNetworkInterface` and `Get-SmbClientNetworkInterface`, as in [SMB Direct: testing](https://learn.microsoft.com/windows-server/storage/file-server/smb-direct#testing-smb-direct)).
2. Compare a large file copy with RDMA disabled and enabled, and watch the `SMB Direct Connection` counters (`Bytes RDMA Read/sec`, `Bytes RDMA Written/sec`) in Performance Monitor, as that page describes.
3. Test path failover: disconnect one path during a large copy and confirm the copy continues on the other.
4. Drive storage load from representative VMs with DiskSpd or [VMFleet](../vmfleet/index.md) and, with the storage network under load, check latency, bandwidth and path failover together. The Well-Architected guidance recommends validating "bandwidth, latency, and path failover with concurrent compute, migration, repair, and backup traffic" ([Architecture best practices for Azure Local](https://learn.microsoft.com/azure/well-architected/service-guides/azure-local#performance-efficiency)).
5. Check DCB, PFC and ETS configuration on every host port and switch port against the [host network requirements](https://learn.microsoft.com/azure/azure-local/concepts/host-network-requirements) when you use RoCE.

I found no Learn page that documents a dedicated `Test-RDMA` script for Azure Local, so none is referenced here.

## Reading an iPerf3 result on an Azure Local network

- Use several parallel streams (`-P`): one TCP stream rarely fills a 25 GbE or faster link.
- Match the MTU on both ends. Jumbo frames are required on some designs and must be consistent end to end.
- Run it in both directions and between each pair of machines (the mesh profile does this).
- Treat a result as a statement about the IP path only.

Status of this tool: see [implementation status](../../reference/status.md). It is unit-tested and not proven on hardware.
