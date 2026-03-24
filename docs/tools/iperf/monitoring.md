# iPerf3 — Monitoring

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

During iPerf3 test runs, host-side network and compute counters are collected and evaluated against the thresholds in `tools/iperf/monitoring/alerts/alert-rules.yml`.

## Alert Rules Reference

| Rule Name | Counter | Threshold | Severity | Rationale |
|-----------|---------|-----------|----------|-----------|
| `iperf_low_throughput` | `\Network Interface(*)\Bytes Total/sec` | < 875 MB/s (7 Gbps) | Warning | Below 70% of 10GbE capacity indicates a network path issue |
| `iperf_interface_saturation` | `\Network Interface(*)\Current Bandwidth` | > 9.9 Gbps | Warning | Near 100% utilization causes TCP retransmits and head-of-line blocking |
| `iperf_high_retransmits` | `\TCPv4\Segments Retransmitted/sec` | > 100/s | Warning | Frequent retransmits indicate network quality or congestion issues |
| `iperf_high_cpu` | `\Processor(_Total)\% Processor Time` | > 80% | Warning | Results may be CPU-bound rather than network-bound |
| `iperf_interrupt_load` | `\Processor(_Total)\% Interrupt Time` | > 30% | Warning | High NIC interrupt rate — RSS/interrupt affinity should be tuned |
| `iperf_low_memory` | `\Memory\Available MBytes` | < 512 MB | Warning | Memory pressure affects TCP socket buffer allocation |

## Understanding iPerf3 Alerts

### Throughput Alerts

**`iperf_low_throughput` (< 875 MB/s)** fires when the actual bytes transferred per second falls below the equivalent of 7 Gbps on a 10GbE interface. This is a meaningful threshold because iPerf3 itself adds some overhead — on a healthy 10GbE link, you should see at least 9.2–9.5 Gbps (1,150+ MB/s). Values near 7 Gbps suggest:

- Duplex mismatch or auto-negotiation failure (check `Get-NetAdapter`)
- Faulty cable or SFP transceiver
- Bandwidth policy or QoS policy throttling

**`iperf_interface_saturation` (> 9.9 Gbps)** fires when a single NIC approaches its rated maximum. For the TCP throughput test, this is expected behavior (you want to see the full 10 Gbps utilized). The alert is informational — it becomes a problem only if you see retransmits alongside saturation, indicating the link cannot absorb the offered load.

### Retransmit Alert

**`iperf_high_retransmits` (> 100/s)** during an iPerf3 TCP test is a strong signal of network quality issues. TCP retransmits during a controlled loopback-scope test (within the cluster) should be near zero on a healthy fabric. Common causes:

- Congestion at a switch port (buffer overflow)
- Mismatched MTU / jumbo frame misconfiguration (`Test-NetConnection` with large datagrams)
- RDMA/RoCE priority flow control not configured

### CPU and Interrupt Alerts

**`iperf_high_cpu` (> 80%)** signals that the test is measuring CPU-to-NIC throughput rather than raw network bandwidth. At high loads on 25GbE/100GbE, a single core can become the bottleneck for network interrupt processing.

**`iperf_interrupt_load` (> 30%)** specifically captures NIC interrupt affinity issues. If interrupt time is high but overall CPU is moderate, use Receive Side Scaling (RSS) to distribute NIC interrupts across cores:

```powershell
# Check and configure RSS on all adapters
Get-NetAdapterRss | Select-Object Name, Enabled, NumberOfReceiveQueues
Set-NetAdapterRss -Name "Storage-NIC" -NumberOfReceiveQueues 8
```

## Monitoring During a Run

```powershell
# View alerts from a completed run log
Get-Content "logs\iperf\<RunId>\iperf-test.log.jsonl" |
    ConvertFrom-Json |
    Where-Object { $_.Severity -in @('WARNING', 'CRITICAL') } |
    Select-Object Timestamp, Severity, Message
```

## Live Counter Monitoring

```powershell
# Monitor network interface counters on a node during the test
Get-Counter `
    '\Network Interface(*)\Bytes Received/sec',
    '\Network Interface(*)\Bytes Sent/sec',
    '\TCPv4\Segments Retransmitted/sec',
    '\Processor(_Total)\% Interrupt Time' `
    -ComputerName "hci01-node1" `
    -SampleInterval 5 -MaxSamples 12 |
    ForEach-Object { $_.CounterSamples } |
    Select-Object Path, CookedValue |
    Format-Table -AutoSize
```
