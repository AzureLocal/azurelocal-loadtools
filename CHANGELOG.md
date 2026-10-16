# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). From the first release on, release-please maintains this file from Conventional Commit messages.

## 1.0.0 (2026-10-16)


### Features

* add central variables.example.yml and gitignore variables.yml (issue [#15](https://github.com/AzureLocal/azurelocal-loadtools/issues/15)) ([def61f6](https://github.com/AzureLocal/azurelocal-loadtools/commit/def61f63ec3ca44f6600474386227f88845fe856))
* add correctly named icon SVG, banner SVG, and update docs home page ([e46f1a6](https://github.com/AzureLocal/azurelocal-loadtools/commit/e46f1a62949f95be75d3e2167c38bf3a3c454d1b)), closes [#22](https://github.com/AzureLocal/azurelocal-loadtools/issues/22)
* add unique project ID field automation (LOAD-N prefix) ([c463d71](https://github.com/AzureLocal/azurelocal-loadtools/commit/c463d71ad2675ea540102f698fe241b2808e1002))
* **claude:** add Claude Code scaffold ([883c0d9](https://github.com/AzureLocal/azurelocal-loadtools/commit/883c0d9b39abc965929e15dc576039f2f5580d47))
* **claude:** add Claude Code scaffold ([0309f6d](https://github.com/AzureLocal/azurelocal-loadtools/commit/0309f6d8344aebec0f0a587b36ef068f3f9b1f15))
* **config:** add missing tool variables to variables.example.yml ([93cddcb](https://github.com/AzureLocal/azurelocal-loadtools/commit/93cddcb9054094b08ce66c10a5931941e872b244))
* GitHub Project & Repo Standardization (Plan 1) ([9aa924e](https://github.com/AzureLocal/azurelocal-loadtools/commit/9aa924e978e1a8494bd579e88b1791e902600986))
* GitHub Project & Repo Standardization (Plan 1) ([5df58c9](https://github.com/AzureLocal/azurelocal-loadtools/commit/5df58c9755389365221f4aa8fde89557ce6641be))
* implement fio, hammerdb, iperf, stress-ng tools ([58ee58c](https://github.com/AzureLocal/azurelocal-loadtools/commit/58ee58cff67a5958d113c126f2a9e14d93b4fb16))
* **reporting:** offline report, baseline comparison with regression exit code, trend, and Day-2 smoke gate ([e2be1f4](https://github.com/AzureLocal/azurelocal-loadtools/commit/e2be1f48496d37a0a68efa3e6f0c2e1d8af2ec2b))
* VMFleet load testing implementation ([2fbcbb6](https://github.com/AzureLocal/azurelocal-loadtools/commit/2fbcbb6d90a539c03934166e1790769a424d3d31))
* **vmfleet:** opt-in failure-injection profile with guarded node-pause and drive-fault helpers ([8909625](https://github.com/AzureLocal/azurelocal-loadtools/commit/890962533c7d37d1ef2b604f565b9499bf6a3635))


### Bug Fixes

* add fetch-depth: 0 to checkout step for drawio-export-action ([442dc58](https://github.com/AzureLocal/azurelocal-loadtools/commit/442dc58337ff883af1df0e1449a12b5d9d162ce1))
* add README.md and remove legacy AsciiDoc files ([#21](https://github.com/AzureLocal/azurelocal-loadtools/issues/21)) ([11df59d](https://github.com/AzureLocal/azurelocal-loadtools/commit/11df59dc9a9602a17011798fe33f36a62c9c9f6d))
* add reopened trigger to add-to-project workflow ([0bf99ba](https://github.com/AzureLocal/azurelocal-loadtools/commit/0bf99ba7f1295509b7e6c978fc1dda63cfb9618d))
* **ci:** result keys no longer collide, suppress analyzer false positive; fix invalid-computer-name test ([98c1275](https://github.com/AzureLocal/azurelocal-loadtools/commit/98c12755103efde63f799e8da8ad2f25d2a1f72f))
* **docs:** inject base path and convert mkdocs admonitions AB[#4945](https://github.com/AzureLocal/azurelocal-loadtools/issues/4945) ([764eab9](https://github.com/AzureLocal/azurelocal-loadtools/commit/764eab92ed8dfbd06cbeff0c3058ab2c57056c66))
* **docs:** restore branding and ignore dead links AB[#4945](https://github.com/AzureLocal/azurelocal-loadtools/issues/4945) ([2ddc18d](https://github.com/AzureLocal/azurelocal-loadtools/commit/2ddc18dccd335b54a8863a201055b15eea58b254))
* **docs:** restore custom navigation, logos, and github links AB[#4945](https://github.com/AzureLocal/azurelocal-loadtools/issues/4945) ([34b45be](https://github.com/AzureLocal/azurelocal-loadtools/commit/34b45becfa1417214a980672f62ccaabfa4c0069))
* **hooks:** substitute {{REPO_ROOT}} placeholder in hook scripts ([1f46785](https://github.com/AzureLocal/azurelocal-loadtools/commit/1f46785c57fae0ea914c6233b81a4c3c9acd3b5b))
* make set-fields resilient to add-to-project failures ([a8ff714](https://github.com/AzureLocal/azurelocal-loadtools/commit/a8ff714e42de898ba9719cab5be5ce348e27099c))
* pin actions/add-to-project to v1.0.2 ([51d5c02](https://github.com/AzureLocal/azurelocal-loadtools/commit/51d5c02b739f73a2062dee818f769f02e5db36e9))
* remove invalid sitemap plugin, move gtag to preset options ([1a88b6d](https://github.com/AzureLocal/azurelocal-loadtools/commit/1a88b6da1edea7f26dc9f9d3d9c730c68d73f490))
* remove old AsciiDoc build-docs.yml workflow ([102e643](https://github.com/AzureLocal/azurelocal-loadtools/commit/102e6431df8decbada20e761668b0526fb0d4914))
* repair failing Pester tests, parse errors, regex bugs, and PSScriptAnalyzer lint exit condition ([abba316](https://github.com/AzureLocal/azurelocal-loadtools/commit/abba316746d8b983834966158cdae5720b481e96))
* repair the 7 failing Pester tests and the bugs behind them ([99fca68](https://github.com/AzureLocal/azurelocal-loadtools/commit/99fca68416893c2359b9e887443ee1e32b9b1594))
* restore docs standards and repair vmfleet tests ([95596ec](https://github.com/AzureLocal/azurelocal-loadtools/commit/95596ec171b6b62da8c64dcea8c9ca38fddd0c43))
* **standards:** update canonical path to docs/standards/ in platform ([21f8ba6](https://github.com/AzureLocal/azurelocal-loadtools/commit/21f8ba6e54b26aa86856894ad91b04c41f27188e))
* update Solution field option IDs after Toolkit option added to Project [#3](https://github.com/AzureLocal/azurelocal-loadtools/issues/3) ([2c9323e](https://github.com/AzureLocal/azurelocal-loadtools/commit/2c9323ea5ac965f35d3b9aba8dc3be7279352cee))
* use action output for item ID, fix stale solution field option IDs ([0248421](https://github.com/AzureLocal/azurelocal-loadtools/commit/024842132a9cb7313993b67ab34d4b73e865b1da))

## [Unreleased]

Target: 0.1.0, the first tagged pre-release. Nothing in this repository has been proven on a live Azure Local cluster; see `docs/reference/status.md`.

### Features

- Opt-in failure injection for VMFleet runs (`FaultInjection` module, `Invoke-VMFleetFault.ps1`, `Undo-VMFleetFault.ps1`, `failure-injection.yml` profile): node pause or one drive out, `-AllowFault` plus confirmation, undo printed first, refuses when the cluster is unhealthy, one fault at a time. Mocked tests only.
- `ResultAnalysis` module: offline HTML and CSV report, baseline comparison with a regression exit code (0 / 1 / 2, fails closed), trend over several runs. `Compare-VMFleetResults.ps1`, `New-VMFleetReport.ps1`.
- Day-2 smoke: `day2-smoke.yml` profile, `Invoke-Day2Smoke.ps1` (exit 0 / 1 / 2 / 3), a JSON result and its schema in `docs/reference`, fixtures validated against it.
- CI: `ci.yml` (PSScriptAnalyzer with a warning budget, Pester one process per suite, link check; actions pinned to SHAs), `release-please.yml`, Dependabot, issue and pull request templates, Azure DevOps validate pipeline with parity.
- Documentation: single implementation-status truth table; CSV in-memory read cache caveat and Well-Architected failure-condition guidance for VMFleet and DiskSpd; Azure Local network guidance for iPerf3 (it does not exercise RDMA).

### Bug Fixes

- `ConfigManager`: a cached configuration no longer hides a bad path (`Import-MasterConfig` now validates the path first and caches per path); the default path is `config/variables/variables.yml`, the file that exists.
- All modules resolved `ProjectRoot` four levels up, outside the repository; it is now the repository root.
- `Deploy-VMFleet.ps1` no longer creates fleet VMs with a hard-coded placeholder password; a `-FleetAdminCredential` is required (also on `Invoke-VMFleetPipeline.ps1`).
- Seven failing Pester tests fixed (StateManager `$using:` in test code, base-image regex, ConfigManager mock scope).

### Miscellaneous

- PSScriptAnalyzer warnings reduced from 545 to 0 by formatting, fixing unused variables and the automatic-variable assignment, and documented rule exclusions in `.psscriptanalyzer.psd1`.
- Module manifests are version 0.1.0; empty `.gitkeep` placeholders removed; the README, roadmap, tool pages and the automation and CI/CD pages no longer claim workflows, scripts or completeness that do not exist.

### VMFleet (earlier, unreleased)

- Add `Prepare-VMFleetBaseImage.ps1` — automates WS2022 Core Gen2 base image download from Azure Local marketplace
- Add `sequential-throughput.yml` workload profile — 512K sequential writes for MB/s ceiling measurement
- Add Azure Monitor workbook (`vmfleet-workbook.json`) with IOPS, latency P95, and throughput panels
- Add KQL queries for Log Analytics (`vmfleet-iops.kql`, `vmfleet-latency.kql`)
- Add `custom_location_id` and `storage_path_id` fields to config schema and example
- Add Pester tests for VMFleet script standards compliance and base image script
- Expand VMFleet documentation: prerequisites, deployment, workload profiles, monitoring, reporting, troubleshooting

### Initial scope (earlier, unreleased)

- VMFleet, fio, iPerf3, HammerDB, and stress-ng load testing scripts
- Modular PowerShell framework (ConfigManager, Logger, StateManager, CredentialManager, MonitoringManager, ReportGenerator)
- Monitoring collectors, dashboards, and alert rules
- Report templates for performance analysis
- Add CONTRIBUTING.md
