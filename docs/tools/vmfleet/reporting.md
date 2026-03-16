# VMFleet Reporting

![Tool: VMFleet](https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square)
![Category: Tool Guide](https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square)

The reporting subsystem generates comprehensive VMFleet test reports in three formats: PDF, Word (DOCX), and Excel (XLSX).

## Report Formats

| Format | Tool | Use Case |
| --- | --- | --- |
| PDF | asciidoctor-pdf with custom theme | Executive summaries, formal documentation, archival |
| DOCX (Word) | Pandoc (AsciiDoc → DocBook → DOCX) | Editable reports, stakeholder collaboration |
| XLSX (Excel) | PowerShell ImportExcel module | Data analysis, pivot tables, custom charting |

## Generating Reports

```powershell
# Generate all three formats from a completed test run
Import-Module ./src/core/powershell/modules/ReportGenerator/ReportGenerator.psm1

New-TestReport `
    -RunId "run-2026-02-13-001" `
    -ResultsPath "results/run-2026-02-13-001/" `
    -OutputPath "reports/run-2026-02-13-001/" `
    -Formats @("PDF", "DOCX", "XLSX") `
    -IncludeMetrics `
    -ClusterConfig "config/clusters/my-cluster.yml"
```

Or generate reports as part of the results collection:

```powershell
.\src\solutions\vmfleet\scripts\Collect-VMFleetResults.ps1 `
    -ResultsPath "results/current-run/" `
    -GenerateReports `
    -ReportFormats @("PDF", "DOCX", "XLSX")
```

## PDF / DOCX Report Sections

Both PDF and DOCX reports contain the same sections:

1. **Cover Page** — Cluster name, test date, run ID, framework version
2. **Executive Summary** — Key findings, pass/fail assessment, top-line metrics
3. **Cluster Configuration** — Node details, storage layout, network configuration
4. **Test Results by Profile** — For each workload profile:
    - IOPS (read/write/total)
    - Throughput (MB/s)
    - Latency (average, P50, P95, P99)
    - Per-node breakdown
5. **Storage Metrics** — Time-series charts for CSVFS counters
6. **Network Metrics** — RDMA/SMB throughput, packet loss summary
7. **Compute Metrics** — Host and guest CPU utilization
8. **Recommendations** — Automated assessment based on metric thresholds
9. **Appendix** — Raw configuration, full variable dump, log excerpts

## Excel Report

The XLSX workbook contains multiple worksheets:

| Sheet | Contents |
| --- | --- |
| Summary | Executive summary with key metrics, conditional formatting (red/yellow/green) |
| Storage Metrics | IOPS, throughput, latency time-series data with line charts |
| Network Metrics | RDMA/SMB throughput, packet loss data with charts |
| Compute Metrics | CPU/memory utilization data with charts |
| Profile Comparison | Side-by-side comparison across workload profiles (pivot table) |
| Raw Data | Complete metric dump for custom analysis |

## Custom Themes

The PDF report uses a custom AsciiDoc theme defined in `docs/themes/azurelocal-theme.yml`:

```yaml
extends: default
page:
  margin: [0.75in, 0.75in, 0.75in, 0.75in]
  size: A4
base:
  font-family: Segoe UI
  font-size: 10
heading:
  font-color: #0078D4
  font-family: Segoe UI Semibold
title-page:
  logo-image: image:azure-local-logo.png[width=200]
```

## Report Templates

Templates in `reports/templates/` define the structure:

- `report-template.adoc` — AsciiDoc template with attribute placeholders for test data
- `cover-page.adoc` — Separated cover page for PDF output
- `excel-template.xlsx` — Pre-formatted Excel workbook with headers, styles, chart templates
