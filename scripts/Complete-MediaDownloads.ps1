#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$jobs = @(Get-BitsTransfer | Where-Object DisplayName -Like 'Northstar*')
if (-not $jobs) {
    Write-Host 'No active Northstar media downloads were found.' -ForegroundColor Yellow
    return
}

foreach ($job in $jobs) {
    switch ($job.JobState) {
        'Transferred' {
            Complete-BitsTransfer -BitsJob $job
            Write-Host "Completed: $($job.DisplayName)" -ForegroundColor Green
        }
        'Error' {
            Write-Error "$($job.DisplayName) failed: $($job.ErrorDescription)"
        }
        'TransientError' {
            Resume-BitsTransfer -BitsJob $job -Asynchronous
            Write-Warning "Resumed transient failure: $($job.DisplayName)"
        }
        default {
            $percent = if ($job.BytesTotal -gt 0) { [math]::Round(($job.BytesTransferred / $job.BytesTotal) * 100, 1) } else { 0 }
            Write-Host "$($job.DisplayName): $percent% ($($job.JobState))"
        }
    }
}

