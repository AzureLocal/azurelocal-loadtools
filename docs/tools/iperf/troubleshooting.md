# iPerf3 — Troubleshooting

![Tool: iPerf3](https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

## iPerf3 Server Fails to Start

**Symptom:** `Start-IperfTest.ps1` reports `bind failed: Address already in use` on port 5201.

**Cause:** A previous test left an iPerf3 server daemon running.

**Resolution:**

```bash
# Kill existing iPerf3 server processes on the node
ssh user@hci01-node1 "pkill -f 'iperf3 -s'; sleep 1; echo done"
```

Then re-run `Start-IperfTest.ps1`. The script sends `pkill` automatically before starting each pair — if it still fails, the process may require a longer delay:

```bash
ssh user@hci01-node1 "pkill -9 -f 'iperf3 -s'; sleep 3"
```

---

## Connection Refused — Port 5201

**Symptom:** Client reports `connect failed: Connection refused` to port 5201 on the server node.

**Resolution:**

1. Verify the firewall on the server node allows inbound TCP/UDP 5201:

```bash
# Linux
ssh user@hci01-node1 "sudo ufw status | grep 5201"
```

```powershell
# Windows
Invoke-Command -ComputerName "hci01-node1" -ScriptBlock {
    Get-NetFirewallRule -DisplayName "iPerf3" | Select-Object Enabled, Direction, Action
}
```

2. Confirm the server is listening: `ssh user@hci01-node1 "ss -tlnp | grep 5201"`

---

## Throughput Below Threshold

**Symptom:** TCP throughput reports 5,000–7,000 MB/s on a 10GbE cluster (threshold: 8,000 MB/s).

**Investigation Steps:**

```powershell
# Check NIC speed and duplex on affected nodes
Get-NetAdapter -CimSession "hci01-node1" |
    Select-Object Name, LinkSpeed, FullDuplex, Status

# Check NIC's current transmit queue length
Get-Counter "\Network Interface(*)\Output Queue Length" `
    -ComputerName "hci01-node1" -SampleInterval 2 -MaxSamples 5
```

**Common Causes:**

| Root Cause | Indicator | Fix |
|------------|-----------|-----|
| NIC auto-negotiated to 1GbE | `LinkSpeed: 1 Gbps` | Check physical cable; set fixed speed on switch |
| Jumbo frames mismatch | Throughput drops with large streams | Set MTU consistently: `Set-NetAdapterAdvancedProperty -Name "NIC" -DisplayName "Jumbo Packet" -DisplayValue "9014 Bytes"` |
| RSS not enabled | `iperf_interrupt_load` alert fires | Enable RSS: `Enable-NetAdapterRss -Name "NIC"` |
| QoS policy throttling | Lower than expected, consistent cap | Check `Get-NetQosPolicy` and `Get-NetQosTrafficClass` |

---

## High Jitter on UDP Profile

**Symptom:** `udp_avg_jitter_ms` exceeds 1.0 ms threshold.

**Investigation:**

```bash
# Run a quick manual jitter test to isolate the issue
ssh user@hci01-node1 "iperf3 -s -D"
ssh user@hci01-node2 "iperf3 -c hci01-node1 -u -b 100M -t 30 --json | python3 -c \
    \"import sys, json; d=json.load(sys.stdin); print('jitter:', d['end']['sum']['jitter_ms'])\""
ssh user@hci01-node1 "pkill -f 'iperf3 -s'"
```

**Common Causes:**

- DSCP/QoS marking not applied to UDP traffic — switch is not prioritizing it
- SFP transceiver marginal — replace and re-test
- Buffer bloat at switch — enable WRED or tail-drop tuning

---

## Mesh Test Shows Asymmetric Throughput

**Symptom:** Per-pair report shows `node1 → node2` at 9,400 MB/s but `node2 → node1` at 6,800 MB/s.

**Investigation:**

```powershell
# Check NIC transmit and receive offload settings
Get-NetAdapterChecksumOffload -CimSession "hci01-node2" | Select-Object Name, *Enabled
Get-NetAdapterLso -CimSession "hci01-node2" | Select-Object Name, *Enabled
```

Asymmetric throughput with offloads enabled/disabled differently per direction is a common NIC configuration mismatch. Also check that NIC firmware is at the same version on all nodes.

---

## SSH Connectivity Issues

**Symptom:** `Start-IperfTest.ps1` fails with `Permission denied (publickey)` when setting up the iPerf3 server.

See the [Operations Troubleshooting Guide](../../operations/troubleshooting.md) for SSH credential resolution steps.
