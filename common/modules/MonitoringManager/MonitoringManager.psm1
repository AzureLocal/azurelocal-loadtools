# =============================================================================
# MonitoringManager Module - Azure Local Load Tools
# =============================================================================
# Manages PerfMon counter collection from cluster nodes with optional push
# to Azure Monitor / Log Analytics.
# =============================================================================

# Module-level variables
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:ActiveCollections = @{}

function Start-MetricCollection {
    <#
    .SYNOPSIS
        Begins background metric collection for specified categories.
    .DESCRIPTION
        Starts background PowerShell jobs that collect PerfMon counters from
        cluster nodes at the specified interval. Writes JSON-lines output files.
    .PARAMETER ClusterNodes
        Array of cluster node hostnames to collect from.
    .PARAMETER Categories
        Metric categories to collect: Storage, Network, Compute.
    .PARAMETER SampleIntervalSeconds
        Seconds between metric samples. Default: 5.
    .PARAMETER OutputPath
        Directory for metric output files.
    .PARAMETER Credential
        PSCredential for remote node access.
    .PARAMETER MaxSamples
        Maximum number of samples to collect (0 = unlimited until stopped).
    .OUTPUTS
        String - Collection ID for use with Stop-MetricCollection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ClusterNodes,

        [Parameter()]
        [ValidateSet('Storage', 'Network', 'Compute')]
        [string[]]$Categories = @('Storage', 'Network', 'Compute'),

        [Parameter()]
        [int]$SampleIntervalSeconds = 5,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [int]$MaxSamples = 0
    )

    $collectionId = "metrics-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # Define counter sets per category
    $counterSets = @{
        'Storage' = @(
            '\Cluster CSVFS(*)\Reads/sec'
            '\Cluster CSVFS(*)\Writes/sec'
            '\Cluster CSVFS(*)\Read Bytes/sec'
            '\Cluster CSVFS(*)\Write Bytes/sec'
            '\Cluster CSVFS(*)\Avg. sec/Read'
            '\Cluster CSVFS(*)\Avg. sec/Write'
            '\PhysicalDisk(*)\Current Disk Queue Length'
            '\PhysicalDisk(*)\Disk Read Bytes/sec'
            '\PhysicalDisk(*)\Disk Write Bytes/sec'
        )
        'Network' = @(
            '\RDMA Activity(*)\RDMA Inbound Bytes/sec'
            '\RDMA Activity(*)\RDMA Outbound Bytes/sec'
            '\SMB Direct Connection(*)\Bytes Sent/sec'
            '\SMB Direct Connection(*)\Bytes Received/sec'
            '\Network Adapter(*)\Bytes Total/sec'
            '\Network Adapter(*)\Packets Outbound Errors'
            '\TCPv4\Segments Retransmitted/sec'
        )
        'Compute' = @(
            '\Processor(_Total)\% Processor Time'
            '\Memory\Available MBytes'
            '\Memory\% Committed Bytes In Use'
            '\Hyper-V Hypervisor Logical Processor(_Total)\% Total Run Time'
            '\Hyper-V Dynamic Memory Balancer(*)\Available Memory'
        )
    }

    $jobs = @()

    foreach ($category in $Categories) {
        $counters = $counterSets[$category]
        $categoryOutputFile = Join-Path $OutputPath "$($category.ToLower())-metrics.jsonl"

        $jobParams = @{
            Name            = "$collectionId-$category"
            ScriptBlock     = {
                param($Nodes, $Counters, $Interval, $OutputFile, $Cred, $MaxSamples)

                $sampleCount = 0
                while ($true) {
                    foreach ($node in $Nodes) {
                        try {
                            $invokeParams = @{
                                ComputerName = $node
                                ScriptBlock  = {
                                    param($CounterPaths, $Interval)
                                    Get-Counter -Counter $CounterPaths -SampleInterval $Interval -MaxSamples 1 -ErrorAction SilentlyContinue
                                }
                                ArgumentList = @(, $Counters), $Interval
                            }

                            if ($Cred) {
                                $invokeParams['Credential'] = $Cred
                            }

                            $samples = Invoke-Command @invokeParams

                            foreach ($sample in $samples.CounterSamples) {
                                $entry = @{
                                    timestamp = (Get-Date -Format 'o')
                                    node      = $node
                                    counter   = $sample.Path -replace "^\\\\[^\\]+\\", '\'
                                    instance  = $sample.InstanceName
                                    value     = [math]::Round($sample.CookedValue, 4)
                                } | ConvertTo-Json -Compress

                                Add-Content -Path $OutputFile -Value $entry -Encoding UTF8
                            }
                        }
                        catch {
                            $errorEntry = @{
                                timestamp = (Get-Date -Format 'o')
                                node      = $node
                                error     = $_.Exception.Message
                            } | ConvertTo-Json -Compress
                            Add-Content -Path $OutputFile -Value $errorEntry -Encoding UTF8
                        }
                    }

                    $sampleCount++
                    if ($MaxSamples -gt 0 -and $sampleCount -ge $MaxSamples) { break }
                    Start-Sleep -Seconds $Interval
                }
            }
            ArgumentList    = @($ClusterNodes, $counters, $SampleIntervalSeconds, $categoryOutputFile, $Credential, $MaxSamples)
        }

        $job = Start-Job @jobParams
        $jobs += @{
            Category = $category
            JobId    = $job.Id
            OutputFile = $categoryOutputFile
        }

        Write-Verbose "Started $category metric collection (Job ID: $($job.Id))"
    }

    $script:ActiveCollections[$collectionId] = @{
        CollectionId = $collectionId
        StartedAt    = (Get-Date -Format 'o')
        Categories   = $Categories
        Jobs         = $jobs
        OutputPath   = $OutputPath
    }

    return $collectionId
}

function Stop-MetricCollection {
    <#
    .SYNOPSIS
        Stops background metric collection and finalizes output files.
    .PARAMETER CollectionId
        The collection ID returned by Start-MetricCollection.
    .OUTPUTS
        PSCustomObject with collection summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CollectionId
    )

    if (-not $script:ActiveCollections.ContainsKey($CollectionId)) {
        throw "Collection not found: $CollectionId"
    }

    $collection = $script:ActiveCollections[$CollectionId]

    foreach ($job in $collection.Jobs) {
        $psJob = Get-Job -Id $job.JobId -ErrorAction SilentlyContinue
        if ($psJob -and $psJob.State -eq 'Running') {
            Stop-Job -Id $job.JobId
            Write-Verbose "Stopped $($job.Category) collection job"
        }
        Remove-Job -Id $job.JobId -Force -ErrorAction SilentlyContinue
    }

    $endedAt = Get-Date -Format 'o'
    $startTime = [datetime]$collection.StartedAt

    $summary = [PSCustomObject]@{
        CollectionId     = $CollectionId
        StartedAt        = $collection.StartedAt
        EndedAt          = $endedAt
        DurationSeconds  = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        Categories       = $collection.Categories
        OutputPath       = $collection.OutputPath
        OutputFiles      = $collection.Jobs | ForEach-Object { $_.OutputFile }
    }

    $script:ActiveCollections.Remove($CollectionId)

    # Write summary file
    $summaryPath = Join-Path $collection.OutputPath 'collection-summary.json'
    $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8

    Write-Verbose "Metric collection stopped. Summary: $summaryPath"
    return $summary
}

function Get-MetricSummary {
    <#
    .SYNOPSIS
        Reads collected metrics and produces a summary with aggregations.
    .PARAMETER MetricsPath
        Path to the metrics directory containing .jsonl files.
    .PARAMETER Category
        Specific category to summarize. If omitted, summarizes all.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MetricsPath,

        [Parameter()]
        [ValidateSet('Storage', 'Network', 'Compute')]
        [string]$Category
    )

    $files = if ($Category) {
        Get-ChildItem -Path $MetricsPath -Filter "$($Category.ToLower())-metrics.jsonl"
    }
    else {
        Get-ChildItem -Path $MetricsPath -Filter "*-metrics.jsonl"
    }

    $summary = @{}

    foreach ($file in $files) {
        $lines = Get-Content -Path $file.FullName | Where-Object { $_ -notmatch '"error"' }
        $entries = $lines | ConvertFrom-Json

        $grouped = $entries | Group-Object -Property counter

        foreach ($group in $grouped) {
            $values = $group.Group | ForEach-Object { $_.value } | Where-Object { $_ -ne $null }
            if ($values.Count -gt 0) {
                $summary[$group.Name] = [PSCustomObject]@{
                    Counter    = $group.Name
                    SampleCount = $values.Count
                    Average    = [math]::Round(($values | Measure-Object -Average).Average, 4)
                    Minimum    = [math]::Round(($values | Measure-Object -Minimum).Minimum, 4)
                    Maximum    = [math]::Round(($values | Measure-Object -Maximum).Maximum, 4)
                    P50        = Get-Percentile -Values $values -Percentile 50
                    P95        = Get-Percentile -Values $values -Percentile 95
                    P99        = Get-Percentile -Values $values -Percentile 99
                }
            }
        }
    }

    return $summary.Values
}

function Get-Percentile {
    <#
    .SYNOPSIS
        Calculates the specified percentile from a set of values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Values,

        [Parameter(Mandatory)]
        [int]$Percentile
    )

    $sorted = $Values | Sort-Object
    $index = [math]::Ceiling($Percentile / 100 * $sorted.Count) - 1
    $index = [math]::Max(0, [math]::Min($index, $sorted.Count - 1))
    return [math]::Round($sorted[$index], 4)
}

# Export module members
Export-ModuleMember -Function @(
    'Start-MetricCollection'
    'Stop-MetricCollection'
    'Get-MetricSummary'
)
