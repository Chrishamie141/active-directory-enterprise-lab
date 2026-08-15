#Requires -Version 5.1

[CmdletBinding()]
param(
    [int]$TimeoutMinutes = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'config\virtualbox-config.json') -Raw | ConvertFrom-Json
$reportPath = Join-Path $projectRoot 'reports\host-build.log'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$expectedFiles = @(
    (Join-Path (Join-Path $projectRoot 'media') ([string]$config.DomainController.IsoFile)),
    (Join-Path (Join-Path $projectRoot 'media') ([string]$config.Client.IsoFile))
)

Start-Transcript -Path $reportPath -Append | Out-Null
try {
    Write-Host "[$(Get-Date -Format o)] Waiting for official evaluation media."
    while ((Get-Date) -lt $deadline) {
        $jobs = @(Get-BitsTransfer | Where-Object DisplayName -Like 'Northstar*')
        foreach ($job in $jobs) {
            if ($job.JobState -eq 'Transferred') {
                Complete-BitsTransfer -BitsJob $job
                Write-Host "[$(Get-Date -Format o)] Finalized $($job.DisplayName)."
            }
            elseif ($job.JobState -eq 'TransientError') {
                Resume-BitsTransfer -BitsJob $job -Asynchronous
            }
            elseif ($job.JobState -eq 'Error') {
                throw "$($job.DisplayName) failed: $($job.ErrorDescription)"
            }
        }

        $ready = @($expectedFiles | Where-Object { Test-Path -LiteralPath $_ }).Count
        if ($ready -eq $expectedFiles.Count) { break }
        Start-Sleep -Seconds 15
    }

    if (@($expectedFiles | Where-Object { Test-Path -LiteralPath $_ }).Count -ne $expectedFiles.Count) {
        throw "Media downloads did not finish within $TimeoutMinutes minutes."
    }

    Write-Host "[$(Get-Date -Format o)] Creating VirtualBox VMs."
    & (Join-Path $PSScriptRoot 'New-VirtualBoxLab.ps1')
    if (-not $?) { throw 'VM creation failed.' }
    Write-Host "[$(Get-Date -Format o)] Host build completed successfully."
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
