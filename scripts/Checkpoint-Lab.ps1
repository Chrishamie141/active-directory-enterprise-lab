#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('CleanInstall','DomainConfigured','ClientJoined')]
    [string]$Stage,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\virtualbox-config.json')
)

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$vbox = $config.VBoxManagePath
$targets = switch ($Stage) {
    'CleanInstall' { @($config.DomainController.Name, $config.Client.Name) }
    'DomainConfigured' { @($config.DomainController.Name) }
    'ClientJoined' { @($config.DomainController.Name, $config.Client.Name) }
}
foreach ($vm in $targets) {
    $stateLine = & $vbox showvminfo $vm --machinereadable | Where-Object { $_ -like 'VMState=*' }
    if ($stateLine -ne 'VMState="poweroff"') {
        throw "VM '$vm' must be powered off before taking a checkpoint. Shut down Windows cleanly, then retry."
    }
    & $vbox snapshot $vm take $Stage --description "Northstar AD lab: $Stage"
    if ($LASTEXITCODE -ne 0) { throw "Snapshot failed for $vm" }
}
