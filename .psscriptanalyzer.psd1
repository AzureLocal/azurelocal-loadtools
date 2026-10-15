# =============================================================================
# PSScriptAnalyzer Settings - Azure Local Load Tools
# =============================================================================
# Usage: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .psscriptanalyzer.psd1
# CI:    pwsh -File tests/Invoke-CiChecks.ps1 -Check Analyzer   (fails on any Error
#        and on more than 50 Warnings)
#
# Every excluded rule is listed with the reason. Real findings are fixed in code;
# the few justified exceptions use a SuppressMessageAttribute next to the code.
# =============================================================================

@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # These are interactive operator scripts. Write-Host output (coloured status,
        # progress banners) is the intended user interface; the data goes to files,
        # the pipeline and the Logger module, not to the host stream.
        'PSAvoidUsingWriteHost'

        # Public function names (Copy-ToClusterNodes, Test-Prerequisites, ...) are already
        # documented in docs/reference/cmdlet-reference.md. Renaming them would break
        # callers for a style-only benefit.
        'PSUseSingularNouns'

        # False positive in PSScriptAnalyzer 1.25: it reports parameters that a Start-Job
        # script block declares itself with param() and receives through -ArgumentList.
        # Those jobs pass every value explicitly, so nothing needs a $using: prefix.
        'PSUseUsingScopeModifierInNewRunspaces'

        # The repo style is Stroustrup (else/catch on a new line after the closing brace),
        # which this rule reports as a violation. PSPlaceOpenBrace and the indentation and
        # whitespace rules stay on.
        'PSPlaceCloseBrace'
    )

    Rules        = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }

        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace  = @{
            Enable                                 = $true
            CheckInnerBrace                        = $true
            CheckOpenBrace                         = $true
            CheckOpenParen                         = $true
            CheckOperator                          = $true
            CheckPipe                              = $true
            CheckPipeForRedundantWhitespace        = $false
            CheckSeparator                         = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }

        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $false
        }
    }
}
