# Failure Injection (opt-in)

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Status: Not proven on hardware](https://img.shields.io/badge/Hardware-Not%20proven-yellow?style=flat-square)

Measure storage performance **while one failure condition is held**: one node paused, or one drive taken out. This is opt-in. It is never part of the pipeline, never part of a default profile, and does nothing without `-AllowFault` and a confirmation.

> [!WARNING]
> This changes the state of the cluster. Run it only on a cluster you own and can lose a copy of the data on. It has been unit-tested with mocks and has **not** been run on a live cluster. Prove it on a non-production cluster first. See [status](../../reference/status.md).

## Why

The Azure Well-Architected Framework guidance for Azure Local recommends using DiskSpd, application benchmarks or SAN vendor tools "from representative VMs to validate latency, throughput, and IOPS under normal and intended failure conditions" ([Architecture best practices for Azure Local](https://learn.microsoft.com/azure/well-architected/service-guides/azure-local#performance-efficiency)). The baseline reference architecture adds that you should test normal and peak demand, updates and maintenance, intended machine and path failures, storage repair and backup ([Azure Local hyperconverged baseline](https://learn.microsoft.com/azure/architecture/hybrid/azure-local-baseline#considerations)). A benchmark taken only on a healthy cluster tells you nothing about the numbers you will see during a node reboot or a drive replacement.

## Faults

| Fault | What it does | Undo |
|-------|--------------|------|
| `NodePause` | Drains the node (`Suspend-ClusterNode -Drain`, polled against a deadline, no `-Wait`), then enables storage maintenance mode for that node | Disable storage maintenance mode, `Resume-ClusterNode -Failback Immediate` |
| `DriveFault` | One named data drive: `Set-PhysicalDisk -Usage Retired` (default) or `Disable-PnpDevice` | Restore the recorded original usage, or `Enable-PnpDevice` |

The module never picks a drive on its own: `-DiskSerialNumber` is required.

## Procedure

```powershell
# 1. Start the workload with the failure-injection profile (20 minutes) in your usual way,
#    for example the pipeline with -ProfilePath tools\vmfleet\config\profiles\failure-injection.yml

# 2. Without -AllowFault the command only prints the plan and the UNDO command
.\tools\vmfleet\scripts\Invoke-VMFleetFault.ps1 -FaultType NodePause -NodeName node01 -ComputerName cluster01.corp.infiniteimprobability.com

# 3. Apply it (you are asked to confirm; the UNDO command is printed first)
.\tools\vmfleet\scripts\Invoke-VMFleetFault.ps1 -FaultType NodePause -NodeName node01 -ComputerName cluster01.corp.infiniteimprobability.com -AllowFault

# 4. Measure the degraded window, then undo and let the repair finish
.\tools\vmfleet\scripts\Undo-VMFleetFault.ps1 -ComputerName cluster01.corp.infiniteimprobability.com -AllowFault
```

The profile `failure-injection.yml` holds the General workload for 20 minutes so you have a baseline window, a degraded window and a repair window to compare. It declares `default_fault: none`; it does not inject anything itself.

## Safeguards

| Safeguard | Behavior |
|-----------|----------|
| Opt-in | `-AllowFault` is a plain switch with no default. Without it: plan only, no remote call, no lock. |
| Confirmation | `ConfirmImpact = 'High'`: you are asked unless you pass `-Confirm:$false` on purpose. |
| Undo first | The UNDO command is printed and returned before anything is changed. |
| Refuses when unhealthy | Pool and every virtual disk Healthy/OK, all nodes Up, every physical disk OK, every CSV Online, no storage (repair) job, no Major/Critical storage fault, witness Online, free pool space of at least one capacity drive per node (maximum four) for repair. |
| Fresh data | The health snapshot must be less than two minutes old, and it is collected again after you confirm. |
| Two nodes | A `NodePause` on a two-node cluster leaves one copy of the data. It is refused unless you add `-AcceptReducedRedundancy`. |
| One fault at a time | A lock file (`state/fault-lock.json`, created atomically) records the fault. A second fault is refused until the undo has completed. |
| Unknown outcome | If the remote call fails or times out, the lock is kept and the error names the undo command. |
| Settled undo | The lock is cleared only after several consecutive polls with no storage job, all volumes Healthy, all nodes Up and all CSVs Online (repair jobs start asynchronously after the undo). |
| Restores what it found | The original drive usage is recorded and restored. The undo refuses to run against a different cluster name than the lock. |
| Input checks | Node names, drive serial numbers and the computer name are validated before they reach a remote script block. |

Known limit: the lock is a local file on the machine you run from. It does not stop a second operator on another machine. Run faults from one designated host.

## What is not proven

- That `Suspend-ClusterNode`, storage maintenance mode and `Set-PhysicalDisk -Usage Retired` behave as the code expects on your release (12.2609 (latest) or any other).
- That the "in maintenance mode" check matches what your cluster reports.
- The repair-reserve rule is the Microsoft planning guideline, not a guarantee that a particular drive can be evacuated.
- The remote cmdlets run only in mocks today. First proof order: preflight output on a healthy cluster (read-only), then a `DriveFault` with `Retire` on a non-production cluster, then `NodePause`.
