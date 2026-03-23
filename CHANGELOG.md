# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Features

- VMFleet, fio, iPerf3, HammerDB, and stress-ng load testing tooling
- Modular PowerShell framework with core and infrastructure modules
- Monitoring collectors, dashboards, and alert rules
- Report templates for performance analysis

### VMFleet

- Add `Prepare-VMFleetBaseImage.ps1` — automates WS2022 Core Gen2 base image download from Azure Local marketplace
- Add `sequential-throughput.yml` workload profile — 512K sequential writes for MB/s ceiling measurement
- Add Azure Monitor workbook (`vmfleet-workbook.json`) with IOPS, latency P95, and throughput panels
- Add KQL queries for Log Analytics (`vmfleet-iops.kql`, `vmfleet-latency.kql`)
- Add `custom_location_id` and `storage_path_id` fields to config schema and example
- Add Pester tests for VMFleet script standards compliance and base image script
- Add PSScriptAnalyzer settings file (`.psscriptanalyzer.psd1`)
- Expand VMFleet documentation: prerequisites, deployment, workload profiles, monitoring, reporting, troubleshooting

### Infrastructure

- Add GitHub Actions workflows for docs, testing, and CI
- Add issue and PR templates
- Add CONTRIBUTING.md
