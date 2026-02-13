# =============================================================================
# ReportGenerator Module - Azure Local Load Tools
# =============================================================================
# Generates test reports in PDF (asciidoctor-pdf), DOCX (Pandoc), and
# XLSX (ImportExcel) formats from collected test results and metrics.
# =============================================================================

# Module-level variables
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path

function New-TestReport {
    <#
    .SYNOPSIS
        Generates test reports in the specified formats.
    .DESCRIPTION
        Creates comprehensive test reports from collected VMFleet results
        and monitoring metrics. Supports PDF, DOCX, and XLSX output.
    .PARAMETER RunId
        The run identifier for the test results.
    .PARAMETER ResultsPath
        Path to the directory containing test results and metrics.
    .PARAMETER OutputPath
        Directory where reports will be written.
    .PARAMETER Formats
        Array of output formats: PDF, DOCX, XLSX.
    .PARAMETER ClusterConfig
        Path to cluster config for including cluster details in report.
    .PARAMETER ReportTitle
        Title for the report. Default from config.
    .PARAMETER ReportAuthor
        Author attribution. Default from config.
    .PARAMETER IncludeMetrics
        Include detailed monitoring metrics in the report.
    .PARAMETER IncludeRawData
        Include raw data worksheets in Excel report.
    .EXAMPLE
        New-TestReport -RunId "run-001" -ResultsPath "results/run-001/" -Formats @("PDF", "DOCX", "XLSX")
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$ResultsPath,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('PDF', 'DOCX', 'XLSX')]
        [string[]]$Formats = @('PDF'),

        [Parameter()]
        [string]$ClusterConfig,

        [Parameter()]
        [string]$ReportTitle = 'Azure Local Load Test Report',

        [Parameter()]
        [string]$ReportAuthor = 'Azure Local Load Tools',

        [Parameter()]
        [switch]$IncludeMetrics,

        [Parameter()]
        [switch]$IncludeRawData
    )

    if (-not $OutputPath) {
        $OutputPath = Join-Path $script:ProjectRoot "reports\$RunId"
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # Load test results
    $testResults = Import-TestResults -ResultsPath $ResultsPath

    # Load metrics if requested
    $metrics = $null
    if ($IncludeMetrics) {
        $metricsPath = Join-Path $ResultsPath 'metrics'
        if (Test-Path $metricsPath) {
            Import-Module (Join-Path $PSScriptRoot '..\MonitoringManager\MonitoringManager.psm1') -ErrorAction SilentlyContinue
            $metrics = Get-MetricSummary -MetricsPath $metricsPath -ErrorAction SilentlyContinue
        }
    }

    foreach ($format in $Formats) {
        if ($PSCmdlet.ShouldProcess("$format report for $RunId", "Generate")) {
            switch ($format) {
                'PDF'  { New-PdfReport -RunId $RunId -TestResults $testResults -Metrics $metrics -OutputPath $OutputPath -Title $ReportTitle -Author $ReportAuthor }
                'DOCX' { New-DocxReport -RunId $RunId -TestResults $testResults -Metrics $metrics -OutputPath $OutputPath -Title $ReportTitle -Author $ReportAuthor }
                'XLSX' { New-XlsxReport -RunId $RunId -TestResults $testResults -Metrics $metrics -OutputPath $OutputPath -Title $ReportTitle -IncludeRawData:$IncludeRawData -ResultsPath $ResultsPath }
            }
        }
    }

    Write-Verbose "Reports generated in: $OutputPath"
    return Get-ChildItem -Path $OutputPath -File
}

function Import-TestResults {
    <#
    .SYNOPSIS
        Loads test results from the results directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResultsPath
    )

    $results = @{
        profiles = @()
        summary  = $null
    }

    # Look for result JSON files
    $resultFiles = Get-ChildItem -Path $ResultsPath -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'collection-summary|run-state' }

    foreach ($file in $resultFiles) {
        try {
            $data = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $results.profiles += $data
        }
        catch {
            Write-Warning "Failed to parse result file: $($file.Name) - $($_.Exception.Message)"
        }
    }

    return $results
}

function New-PdfReport {
    <#
    .SYNOPSIS
        Generates a PDF report using asciidoctor-pdf.
    #>
    [CmdletBinding()]
    param(
        [string]$RunId,
        $TestResults,
        $Metrics,
        [string]$OutputPath,
        [string]$Title,
        [string]$Author
    )

    # Check for asciidoctor-pdf
    $asciidoctorPdf = Get-Command 'asciidoctor-pdf' -ErrorAction SilentlyContinue
    if (-not $asciidoctorPdf) {
        Write-Warning "asciidoctor-pdf not found. Install with: gem install asciidoctor-pdf"
        Write-Warning "Skipping PDF generation."
        return
    }

    # Generate AsciiDoc content from template
    $templatePath = Join-Path $script:ProjectRoot 'reports\templates\report-template.adoc'
    $generatedAdoc = Join-Path $OutputPath "$RunId-report.adoc"
    $outputPdf = Join-Path $OutputPath "$RunId-report.pdf"
    $themePath = Join-Path $script:ProjectRoot 'docs\themes\azurelocal-theme.yml'

    # Build report content
    $content = @"
= $Title
$Author
:revdate: $(Get-Date -Format 'yyyy-MM-dd')
:doctype: article
:toc: left
:toclevels: 2
:sectnums:
:icons: font

== Executive Summary

* *Run ID:* $RunId
* *Date:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
* *Profiles Tested:* $($TestResults.profiles.Count)

== Test Results

"@

    if ($TestResults.profiles.Count -gt 0) {
        foreach ($profile in $TestResults.profiles) {
            $content += @"

=== Profile: $($profile.profile_name ?? 'Unknown')

[cols='2,1']
|===
| Metric | Value

| Total IOPS
| $($profile.total_iops ?? 'N/A')

| Read Throughput (MB/s)
| $($profile.read_throughput_mbps ?? 'N/A')

| Write Throughput (MB/s)
| $($profile.write_throughput_mbps ?? 'N/A')

| Average Latency (ms)
| $($profile.avg_latency_ms ?? 'N/A')
|===

"@
        }
    }
    else {
        $content += "`nNo test results found. Run a VMFleet test first.`n"
    }

    if ($Metrics) {
        $content += @"

== Monitoring Metrics

[cols='3,1,1,1,1']
|===
| Counter | Average | Min | Max | P95

"@
        foreach ($m in $Metrics) {
            $content += "| $($m.Counter) | $($m.Average) | $($m.Minimum) | $($m.Maximum) | $($m.P95)`n"
        }
        $content += "|===`n"
    }

    Set-Content -Path $generatedAdoc -Value $content -Encoding UTF8

    # Build PDF
    $pdfArgs = @($generatedAdoc, '-o', $outputPdf)
    if (Test-Path $themePath) {
        $pdfArgs += @('-a', "pdf-theme=$themePath")
    }

    Write-Verbose "Generating PDF: $outputPdf"
    & asciidoctor-pdf @pdfArgs

    if (Test-Path $outputPdf) {
        Write-Verbose "PDF report generated: $outputPdf"
    }
    else {
        Write-Warning "PDF generation may have failed. Check asciidoctor-pdf output."
    }
}

function New-DocxReport {
    <#
    .SYNOPSIS
        Generates a DOCX report via AsciiDoc → DocBook → Pandoc.
    #>
    [CmdletBinding()]
    param(
        [string]$RunId,
        $TestResults,
        $Metrics,
        [string]$OutputPath,
        [string]$Title,
        [string]$Author
    )

    $asciidoctor = Get-Command 'asciidoctor' -ErrorAction SilentlyContinue
    $pandoc = Get-Command 'pandoc' -ErrorAction SilentlyContinue

    if (-not $asciidoctor) {
        Write-Warning "asciidoctor not found. Install with: gem install asciidoctor"
        return
    }
    if (-not $pandoc) {
        Write-Warning "pandoc not found. Install with: winget install JohnMacFarlane.Pandoc"
        return
    }

    $adocFile = Join-Path $OutputPath "$RunId-report.adoc"
    $docbookFile = Join-Path $OutputPath "$RunId-report.xml"
    $docxFile = Join-Path $OutputPath "$RunId-report.docx"

    if (-not (Test-Path $adocFile)) {
        # Generate the AsciiDoc first via the PDF function (it creates the .adoc)
        New-PdfReport -RunId $RunId -TestResults $TestResults -Metrics $Metrics -OutputPath $OutputPath -Title $Title -Author $Author
    }

    if (Test-Path $adocFile) {
        # AsciiDoc → DocBook XML
        Write-Verbose "Converting AsciiDoc to DocBook XML..."
        & asciidoctor -b docbook $adocFile -o $docbookFile

        # DocBook → DOCX via Pandoc
        Write-Verbose "Converting DocBook to DOCX via Pandoc..."
        & pandoc -f docbook -t docx -o $docxFile $docbookFile

        if (Test-Path $docxFile) {
            Write-Verbose "DOCX report generated: $docxFile"
        }

        # Clean up intermediate DocBook file
        Remove-Item -Path $docbookFile -ErrorAction SilentlyContinue
    }
}

function New-XlsxReport {
    <#
    .SYNOPSIS
        Generates an XLSX report using the ImportExcel module.
    #>
    [CmdletBinding()]
    param(
        [string]$RunId,
        $TestResults,
        $Metrics,
        [string]$OutputPath,
        [string]$Title,
        [switch]$IncludeRawData,
        [string]$ResultsPath
    )

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Warning "ImportExcel module not found. Install with: Install-Module ImportExcel"
        return
    }

    Import-Module ImportExcel -ErrorAction Stop

    $xlsxFile = Join-Path $OutputPath "$RunId-report.xlsx"

    # Summary sheet
    $summaryData = @([PSCustomObject]@{
        RunId           = $RunId
        Date            = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ProfilesTested  = $TestResults.profiles.Count
        Status          = 'Completed'
    })

    $summaryData | Export-Excel -Path $xlsxFile -WorksheetName 'Summary' `
        -AutoSize -BoldTopRow -FreezeTopRow -Title $Title

    # Test results sheet (if data available)
    if ($TestResults.profiles.Count -gt 0) {
        $TestResults.profiles | Export-Excel -Path $xlsxFile -WorksheetName 'Test Results' `
            -AutoSize -BoldTopRow -FreezeTopRow -Append
    }

    # Metrics sheets
    if ($Metrics) {
        $Metrics | Export-Excel -Path $xlsxFile -WorksheetName 'Metrics Summary' `
            -AutoSize -BoldTopRow -FreezeTopRow -Append
    }

    # Raw data sheet
    if ($IncludeRawData -and $ResultsPath) {
        $metricsDir = Join-Path $ResultsPath 'metrics'
        if (Test-Path $metricsDir) {
            $rawFiles = Get-ChildItem -Path $metricsDir -Filter '*.jsonl'
            foreach ($rawFile in $rawFiles) {
                $rawData = Get-Content -Path $rawFile.FullName |
                    Where-Object { $_ -notmatch '"error"' } |
                    ConvertFrom-Json

                if ($rawData.Count -gt 0) {
                    $sheetName = "Raw - $($rawFile.BaseName)" -replace '-metrics$', ''
                    $sheetName = $sheetName.Substring(0, [math]::Min(31, $sheetName.Length))  # Excel 31-char limit
                    $rawData | Export-Excel -Path $xlsxFile -WorksheetName $sheetName `
                        -AutoSize -BoldTopRow -FreezeTopRow -Append
                }
            }
        }
    }

    if (Test-Path $xlsxFile) {
        Write-Verbose "XLSX report generated: $xlsxFile"
    }
}

# Export module members
Export-ModuleMember -Function @(
    'New-TestReport'
    'Import-TestResults'
)
