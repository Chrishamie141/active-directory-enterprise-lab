#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\virtualbox-config.json'),
    [switch]$StartDomainController
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-VBox {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & $script:VBoxManage @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "VBoxManage failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

function Test-VmExists {
    param([Parameter(Mandatory)][string]$Name)
    $registeredVms = (& $script:VBoxManage list vms) -join "`n"
    return $registeredVms -match ('"' + [regex]::Escape($Name) + '"')
}

function New-LabVm {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][bool]$RequireTpm
    )

    $name = [string]$Definition.Name
    if (Test-VmExists -Name $name) {
        Write-Host "VM already exists: $name" -ForegroundColor Yellow
        return
    }

    $vmFolder = Join-Path $script:VmBaseFolder $name
    $diskPath = Join-Path $vmFolder "$name.vdi"
    if (-not $PSCmdlet.ShouldProcess($name, 'Create and configure VirtualBox VM')) { return }

    Invoke-VBox @('createvm', '--name', $name, '--ostype', [string]$Definition.OsType, '--basefolder', $script:VmBaseFolder, '--register')
    $modifyArgs = @(
        'modifyvm', $name,
        '--memory', [string]$Definition.MemoryMB,
        '--cpus', [string]$Definition.Cpus,
        '--vram', '128',
        '--graphicscontroller', 'vboxsvga',
        '--firmware', 'efi',
        '--ioapic', 'on',
        '--rtc-use-utc', 'on',
        '--clipboard-mode', 'hosttoguest',
        '--drag-and-drop', 'disabled',
        '--audio-enabled', 'off',
        '--usb-xhci', 'on',
        '--nic1', 'hostonly',
        '--host-only-adapter1', [string]$script:Config.HostOnlyAdapter,
        '--nic-type1', '82540EM',
        '--nic2', 'nat',
        '--nic-type2', '82540EM',
        '--boot1', 'dvd',
        '--boot2', 'disk'
    )
    if ($RequireTpm) { $modifyArgs += @('--tpm-type', '2.0') }
    Invoke-VBox $modifyArgs
    Invoke-VBox @('createmedium', 'disk', '--filename', $diskPath, '--size', [string]$Definition.DiskMB, '--format', 'VDI', '--variant', 'Standard')
    Invoke-VBox @('storagectl', $name, '--name', 'SATA Controller', '--add', 'sata', '--controller', 'IntelAhci', '--portcount', '3', '--bootable', 'on')
    Invoke-VBox @('storageattach', $name, '--storagectl', 'SATA Controller', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $diskPath)
    Invoke-VBox @('storageattach', $name, '--storagectl', 'SATA Controller', '--port', '1', '--device', '0', '--type', 'dvddrive', '--medium', $IsoPath)
    Invoke-VBox @('sharedfolder', 'add', $name, '--name', 'NorthstarLab', '--hostpath', $script:ProjectRoot, '--readonly', '--automount')
    Write-Host "Created $name" -ForegroundColor Green
}

$script:Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$script:VBoxManage = [string]$Config.VBoxManagePath
$script:ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:MediaPath = Join-Path $ProjectRoot 'media'
$script:VmBaseFolder = Join-Path $env:USERPROFILE ([string]$Config.VmBaseFolder)

if (-not (Test-Path -LiteralPath $VBoxManage)) { throw "VBoxManage was not found at $VBoxManage" }
if (-not (Test-Path -LiteralPath $VmBaseFolder) -and -not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $VmBaseFolder -Force | Out-Null
}

$hostOnlyOutput = & $VBoxManage list hostonlyifs
$hostOnlyText = $hostOnlyOutput -join "`n"
if ($hostOnlyText -notmatch [regex]::Escape([string]$Config.HostOnlyAdapter)) {
    throw "Host-only adapter '$($Config.HostOnlyAdapter)' was not found."
}
if ($hostOnlyText -notmatch [regex]::Escape([string]$Config.Network.HostAddress)) {
    throw "The host-only adapter does not have expected address $($Config.Network.HostAddress)."
}

$serverIso = Join-Path $MediaPath ([string]$Config.DomainController.IsoFile)
$clientIso = Join-Path $MediaPath ([string]$Config.Client.IsoFile)
foreach ($iso in @($serverIso, $clientIso)) {
    if (-not (Test-Path -LiteralPath $iso)) {
        if ($WhatIfPreference) {
            Write-Warning "Previewing with ISO not yet ready: $iso"
        }
        else {
            throw "Required ISO is not ready: $iso. Run Complete-MediaDownloads.ps1 after the BITS jobs finish."
        }
    }
}

New-LabVm -Definition $Config.DomainController -IsoPath $serverIso -RequireTpm $false
New-LabVm -Definition $Config.Client -IsoPath $clientIso -RequireTpm $true

if ($StartDomainController -and $PSCmdlet.ShouldProcess($Config.DomainController.Name, 'Start VM with graphical console')) {
    Invoke-VBox @('startvm', [string]$Config.DomainController.Name, '--type', 'gui')
}

Write-Host 'VirtualBox lab is ready. Install Windows Server first, then follow docs/virtualbox-runbook.md.' -ForegroundColor Cyan
