#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\virtualbox-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$mediaPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\media'))

Write-Host 'Evaluation media' -ForegroundColor Cyan
Get-BitsTransfer -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Like 'Northstar*' |
    Select-Object DisplayName, JobState,
        @{Name='TransferredGB'; Expression={ [math]::Round($_.BytesTransferred / 1GB, 2) }},
        @{Name='TotalGB'; Expression={ [math]::Round($_.BytesTotal / 1GB, 2) }} |
    Format-Table -AutoSize

$mediaRows = foreach ($file in @($config.DomainController.IsoFile, $config.Client.IsoFile)) {
    $path = Join-Path $mediaPath $file
    [pscustomobject]@{
        File = $file
        Ready = Test-Path -LiteralPath $path
        SizeGB = if (Test-Path -LiteralPath $path) { [math]::Round((Get-Item -LiteralPath $path).Length / 1GB, 2) } else { 0 }
    }
}
$mediaRows | Format-Table -AutoSize

Write-Host 'Virtual machines' -ForegroundColor Cyan
$vbox = $config.VBoxManagePath
if (Test-Path -LiteralPath $vbox) {
    & $vbox list vms
    & $vbox list runningvms
}
else {
    Write-Warning "VBoxManage was not found at $vbox"
}
