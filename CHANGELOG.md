# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.0 (2026-05-12)


### Features

* add central variables.example.yml and gitignore variables.yml (issue [#15](https://github.com/AzureLocal/azurelocal-loadtools/issues/15)) ([def61f6](https://github.com/AzureLocal/azurelocal-loadtools/commit/def61f63ec3ca44f6600474386227f88845fe856))
* add correctly named icon SVG, banner SVG, and update docs home page ([e46f1a6](https://github.com/AzureLocal/azurelocal-loadtools/commit/e46f1a62949f95be75d3e2167c38bf3a3c454d1b)), closes [#22](https://github.com/AzureLocal/azurelocal-loadtools/issues/22)
* add unique project ID field automation (LOAD-N prefix) ([c463d71](https://github.com/AzureLocal/azurelocal-loadtools/commit/c463d71ad2675ea540102f698fe241b2808e1002))
* **config:** add missing tool variables to variables.example.yml ([93cddcb](https://github.com/AzureLocal/azurelocal-loadtools/commit/93cddcb9054094b08ce66c10a5931941e872b244))
* GitHub Project & Repo Standardization (Plan 1) ([9aa924e](https://github.com/AzureLocal/azurelocal-loadtools/commit/9aa924e978e1a8494bd579e88b1791e902600986))
* GitHub Project & Repo Standardization (Plan 1) ([5df58c9](https://github.com/AzureLocal/azurelocal-loadtools/commit/5df58c9755389365221f4aa8fde89557ce6641be))
* implement fio, hammerdb, iperf, stress-ng tools ([58ee58c](https://github.com/AzureLocal/azurelocal-loadtools/commit/58ee58cff67a5958d113c126f2a9e14d93b4fb16))
* VMFleet load testing implementation ([2fbcbb6](https://github.com/AzureLocal/azurelocal-loadtools/commit/2fbcbb6d90a539c03934166e1790769a424d3d31))


### Bug Fixes

* add fetch-depth: 0 to checkout step for drawio-export-action ([442dc58](https://github.com/AzureLocal/azurelocal-loadtools/commit/442dc58337ff883af1df0e1449a12b5d9d162ce1))
* add README.md and remove legacy AsciiDoc files ([#21](https://github.com/AzureLocal/azurelocal-loadtools/issues/21)) ([11df59d](https://github.com/AzureLocal/azurelocal-loadtools/commit/11df59dc9a9602a17011798fe33f36a62c9c9f6d))
* add reopened trigger to add-to-project workflow ([0bf99ba](https://github.com/AzureLocal/azurelocal-loadtools/commit/0bf99ba7f1295509b7e6c978fc1dda63cfb9618d))
* make set-fields resilient to add-to-project failures ([a8ff714](https://github.com/AzureLocal/azurelocal-loadtools/commit/a8ff714e42de898ba9719cab5be5ce348e27099c))
* pin actions/add-to-project to v1.0.2 ([51d5c02](https://github.com/AzureLocal/azurelocal-loadtools/commit/51d5c02b739f73a2062dee818f769f02e5db36e9))
* remove invalid sitemap plugin, move gtag to preset options ([1a88b6d](https://github.com/AzureLocal/azurelocal-loadtools/commit/1a88b6da1edea7f26dc9f9d3d9c730c68d73f490))
* remove old AsciiDoc build-docs.yml workflow ([102e643](https://github.com/AzureLocal/azurelocal-loadtools/commit/102e6431df8decbada20e761668b0526fb0d4914))
* repair failing Pester tests, parse errors, regex bugs, and PSScriptAnalyzer lint exit condition ([abba316](https://github.com/AzureLocal/azurelocal-loadtools/commit/abba316746d8b983834966158cdae5720b481e96))
* restore docs standards and repair vmfleet tests ([95596ec](https://github.com/AzureLocal/azurelocal-loadtools/commit/95596ec171b6b62da8c64dcea8c9ca38fddd0c43))
* **standards:** update canonical path to docs/standards/ in platform ([21f8ba6](https://github.com/AzureLocal/azurelocal-loadtools/commit/21f8ba6e54b26aa86856894ad91b04c41f27188e))
* update Solution field option IDs after Toolkit option added to Project [#3](https://github.com/AzureLocal/azurelocal-loadtools/issues/3) ([2c9323e](https://github.com/AzureLocal/azurelocal-loadtools/commit/2c9323ea5ac965f35d3b9aba8dc3be7279352cee))
* use action output for item ID, fix stale solution field option IDs ([0248421](https://github.com/AzureLocal/azurelocal-loadtools/commit/024842132a9cb7313993b67ab34d4b73e865b1da))

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
