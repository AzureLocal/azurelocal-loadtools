# Badge Standards — Azure Local Load Tools

![Category: Standards](https://img.shields.io/badge/Category-Standards-E67E22?style=flat-square)
![Updated: 2026-02-16](https://img.shields.io/badge/Updated-2026--02--16-lightgrey?style=flat-square)

This document defines the standard badges used across all `.adoc` files in the Azure Local Load Tools repository.
Badges provide at-a-glance metadata — platform, tool, status, audience, and version — rendered as shields.io image macros.

## Quick Navigation

- [Badge Syntax](#badge-syntax) — AsciiDoc syntax for rendering badges
- [Badge Catalog](#badge-catalog) — Complete list of all project badges
- [Badge Placement](#badge-placement-rules) — Where badges go in each document tier
- [Custom Badges](#creating-custom-badges) — How to create new badges

---

## Badge Syntax

Badges use the shields.io static badge service rendered as AsciiDoc inline image macros:

```asciidoc
image:https://img.shields.io/badge/{LABEL}-{VALUE}-{COLOR}?style=flat-square&logo={LOGO}[{ALT TEXT}]
```

**URL Encoding Rules**

- Spaces → `%20`
- Hyphens in values → `--` (double dash)
- Underscores → `__` (double underscore)

**Style**

All badges in this project use `?style=flat-square` for visual consistency.

## Badge Catalog

### Platform & Project Badges

Used on root README and `docs/index.adoc`.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Platform** | `image:https://img.shields.io/badge/Platform-Azure%20Local-0078D4?style=flat-square&logo=microsoft-azure[Platform: Azure Local]` | Platform: Azure Local |
| **PowerShell Version** | `image:https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?style=flat-square&logo=powershell[PowerShell 7.2+]` | PowerShell 7.2+ |
| **License** | `image:https://img.shields.io/badge/License-MIT-green?style=flat-square[License: MIT]` | License: MIT |
| **Project Status** | `image:https://img.shields.io/badge/Status-Pre--Release-orange?style=flat-square[Status: Pre-Release]` | Status: Pre-Release |
| **Docs Hub** | `image:https://img.shields.io/badge/Docs-index.adoc-blue?style=flat-square&logo=readthedocs[Docs]` | Docs: index.adoc |

### Tool Badges

Identify which load testing tool a document covers. Used on tool guide pages and tool-specific READMEs.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **VMFleet** | `image:https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square[Tool: VMFleet]` | Tool: VMFleet |
| **fio** | `image:https://img.shields.io/badge/Tool-fio-6C3483?style=flat-square[Tool: fio]` | Tool: fio |
| **iPerf3** | `image:https://img.shields.io/badge/Tool-iPerf3-1ABC9C?style=flat-square[Tool: iPerf3]` | Tool: iPerf3 |
| **HammerDB** | `image:https://img.shields.io/badge/Tool-HammerDB-E74C3C?style=flat-square[Tool: HammerDB]` | Tool: HammerDB |
| **stress-ng** | `image:https://img.shields.io/badge/Tool-stress--ng-F39C12?style=flat-square[Tool: stress-ng]` | Tool: stress-ng |

### Version Badges

Show the version of a tool or component. Used on tool overview pages.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **VMFleet Version** | `image:https://img.shields.io/badge/VMFleet-2.1.0.0-blue?style=flat-square[VMFleet 2.1.0.0]` | VMFleet 2.1.0.0 |
| **DiskSpd Version** | `image:https://img.shields.io/badge/DiskSpd-2.2-blue?style=flat-square[DiskSpd 2.2]` | DiskSpd 2.2 |
| **Ansible Version** | `image:https://img.shields.io/badge/Ansible-2.14%2B-EE0000?style=flat-square&logo=ansible[Ansible 2.14+]` | Ansible 2.14+ |

### Implementation Status Badges

Indicate whether a tool or feature is implemented. Used on tool overview pages and READMEs.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Fully Implemented** | `image:https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square[Status: Implemented]` | Status: Implemented |
| **In Progress** | `image:https://img.shields.io/badge/Status-In%20Progress-yellow?style=flat-square[Status: In Progress]` | Status: In Progress |
| **Placeholder** | `image:https://img.shields.io/badge/Status-Placeholder-lightgrey?style=flat-square[Status: Placeholder]` | Status: Placeholder |
| **Deprecated** | `image:https://img.shields.io/badge/Status-Deprecated-red?style=flat-square[Status: Deprecated]` | Status: Deprecated |

### Document Category Badges

Identify the type/category of the document. Used on guide documents.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Getting Started** | `image:https://img.shields.io/badge/Category-Getting%20Started-2ECC71?style=flat-square[Category: Getting Started]` | Category: Getting Started |
| **Tool Guide** | `image:https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square[Category: Tool Guide]` | Category: Tool Guide |
| **Operations** | `image:https://img.shields.io/badge/Category-Operations-9B59B6?style=flat-square[Category: Operations]` | Category: Operations |
| **Reference** | `image:https://img.shields.io/badge/Category-Reference-7F8C8D?style=flat-square[Category: Reference]` | Category: Reference |
| **Standards** | `image:https://img.shields.io/badge/Category-Standards-E67E22?style=flat-square[Category: Standards]` | Category: Standards |

### Audience & Difficulty Badges

Indicate the intended audience or skill level. Used on getting-started and tool guide pages.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Beginner** | `image:https://img.shields.io/badge/Level-Beginner-brightgreen?style=flat-square[Level: Beginner]` | Level: Beginner |
| **Intermediate** | `image:https://img.shields.io/badge/Level-Intermediate-yellow?style=flat-square[Level: Intermediate]` | Level: Intermediate |
| **Advanced** | `image:https://img.shields.io/badge/Level-Advanced-red?style=flat-square[Level: Advanced]` | Level: Advanced |

### Audience Role Badges

Identify the target reader role. Used on guide documents.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Infrastructure Engineer** | `image:https://img.shields.io/badge/Audience-Infra%20Engineer-0078D4?style=flat-square[Audience: Infra Engineer]` | Audience: Infra Engineer |
| **DevOps Engineer** | `image:https://img.shields.io/badge/Audience-DevOps-5C2D91?style=flat-square[Audience: DevOps]` | Audience: DevOps |
| **Storage Admin** | `image:https://img.shields.io/badge/Audience-Storage%20Admin-2E86C1?style=flat-square[Audience: Storage Admin]` | Audience: Storage Admin |
| **Network Engineer** | `image:https://img.shields.io/badge/Audience-Network%20Engineer-1ABC9C?style=flat-square[Audience: Network Engineer]` | Audience: Network Engineer |
| **DBA** | `image:https://img.shields.io/badge/Audience-DBA-E74C3C?style=flat-square[Audience: DBA]` | Audience: DBA |

### OS & Environment Badges

Indicate required operating system or execution environment. Used on prerequisites and tool pages.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Windows** | `image:https://img.shields.io/badge/OS-Windows-0078D6?style=flat-square&logo=windows[OS: Windows]` | OS: Windows |
| **Linux** | `image:https://img.shields.io/badge/OS-Linux-FCC624?style=flat-square&logo=linux&logoColor=black[OS: Linux]` | OS: Linux |
| **WSL2** | `image:https://img.shields.io/badge/OS-WSL2-FCC624?style=flat-square&logo=linux&logoColor=black[OS: WSL2]` | OS: WSL2 |

### CI/CD Pipeline Badges

Show pipeline status (link to actual workflows once created). Used on root README.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Build Docs** | `image:https://img.shields.io/github/actions/workflow/status/AzureLocal/azurelocal-loadtools/build-docs.yml?style=flat-square&label=Docs%20Build[Docs Build]` | Docs Build: passing |
| **Tests** | `image:https://img.shields.io/github/actions/workflow/status/AzureLocal/azurelocal-loadtools/run-tests.yml?style=flat-square&label=Tests[Tests]` | Tests: passing |
| **Lint** | `image:https://img.shields.io/github/actions/workflow/status/AzureLocal/azurelocal-loadtools/lint.yml?style=flat-square&label=Lint[Lint]` | Lint: passing |

!!! note
    CI/CD badges use the GitHub Actions workflow status endpoint. These will show actual pass/fail status once the workflows exist.

### Last Updated Badge

Show when a document was last modified. Used on any document where freshness matters.

| Badge | AsciiDoc Syntax | Preview Text |
| --- | --- | --- |
| **Last Updated** | `image:https://img.shields.io/badge/Updated-2026--02--16-lightgrey?style=flat-square[Updated: 2026-02-16]` | Updated: 2026-02-16 |

!!! tip
    Update the date in the badge URL each time the document is modified. Use ISO 8601 format (`YYYY-MM-DD`) with double-dash escaping.

## Badge Placement Rules

### Placement by Document Tier

| Tier | Badge Placement |
| --- | --- |
| **Standards** | After all attributes, before the `[abstract]` block. One badge per line. |
| **Guides** | After all attributes, before the first content paragraph. One badge per line. |
| **READMEs** | After all attributes, before the first content paragraph. Badges on the same line (inline) separated by a space. |

### Example: Guide with Badges

```asciidoc
= VMFleet Deployment
:toc: left
:toclevels: 3
...

image:https://img.shields.io/badge/Tool-VMFleet-0078D4?style=flat-square[Tool: VMFleet]
image:https://img.shields.io/badge/Category-Tool%20Guide-3498DB?style=flat-square[Category: Tool Guide]
image:https://img.shields.io/badge/Status-Implemented-brightgreen?style=flat-square[Status: Implemented]

This guide covers installing the VMFleet module...
```

### Example: Standards with Badges

```asciidoc
= Document Title — Subtitle
Kristopher Turner
v1.0, 2026-02-16

:description: ...
:toc: left
...

image:https://img.shields.io/badge/Category-Standards-E67E22?style=flat-square[Category: Standards]

[abstract]
One to three sentences.
```

### Example: README with Badges

```asciidoc
= Azure Local Load Tools
:toc: macro
:toclevels: 2
:icons: font

image:https://img.shields.io/badge/Platform-Azure%20Local-0078D4?style=flat-square&logo=microsoft-azure[Platform] image:https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?style=flat-square&logo=powershell[PowerShell] image:https://img.shields.io/badge/License-MIT-green?style=flat-square[License]

Comprehensive load testing framework...

toc::[]
```

!!! note
    In READMEs, placing badges on the same line (separated by spaces) renders them as an inline row. In guides and standards, one badge per line stacks vertically.

### Required Badges by Location

| Document | Required Badges |
| --- | --- |
| Root `README.adoc` | Platform, PowerShell Version, License, Project Status |
| `docs/index.adoc` | Platform, Project Status |
| `docs/getting-started/*.adoc` | Category (Getting Started) |
| `docs/tools/{tool}/overview.adoc` | Tool, Status (Implemented/Placeholder), Version (if applicable) |
| `docs/tools/{tool}/*.adoc` (other) | Tool, Category (Tool Guide) |
| `docs/operations/*.adoc` | Category (Operations) |
| `docs/reference/*.adoc` | Category (Reference) |
| `docs/standards/*.adoc` | Category (Standards) |
| `src/solutions/*/README.md` | Tool, Status |

!!! tip
    Audience, Level, OS, and Last Updated badges are **optional** — add them when they provide meaningful context.

## Creating Custom Badges

To create a new badge not listed in the catalog:

1. Go to [https://shields.io/badges/static-badge](https://shields.io/badges/static-badge)
2. Set the label, value, and color
3. Always use `?style=flat-square` for consistency
4. Add `&logo={logo-name}` if an appropriate [Simple Icons](https://simpleicons.org) logo exists
5. Add the new badge to this standards document before using it in other files

### Color Palette

Use these colors for consistency across the project:

| Color | Hex | Usage |
| --- | --- | --- |
| `0078D4` | Microsoft Blue | Platform, Azure-related, VMFleet |
| `5391FE` | PowerShell Blue | PowerShell version |
| `brightgreen` | (shields default) | Implemented, Beginner, positive status |
| `green` | (shields default) | License, Getting Started category |
| `yellow` | (shields default) | In Progress, Intermediate |
| `orange` | (shields default) | Pre-Release, Standards category |
| `red` | (shields default) | Deprecated, Advanced |
| `lightgrey` | (shields default) | Placeholder, Last Updated, neutral |
| `6C3483` | Purple | fio tool |
| `1ABC9C` | Teal | iPerf3 tool, Network Engineer |
| `E74C3C` | Red | HammerDB tool, DBA |
| `F39C12` | Amber | stress-ng tool |
| `3498DB` | Blue | Tool Guide category |
| `9B59B6` | Violet | Operations category |
| `7F8C8D` | Grey | Reference category |
