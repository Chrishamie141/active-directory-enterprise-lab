#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ComputerName = 'NS-WIN11-01',
    [string]$DomainDnsName = 'ad.northstar.test',
    [string]$DomainControllerAddress = '192.168.56.10',
    [string]$ComputerOU = 'OU=Workstations,OU=Northstar,DC=ad,DC=northstar,DC=test'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostOnly = Get-NetAdapter | Where-Object Status -eq 'Up' | Where-Object {
    -not (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway
} | Select-Object -First 1
if (-not $hostOnly) { throw 'Could not identify the host-only network adapter.' }

Set-DnsClientServerAddress -InterfaceIndex $hostOnly.ifIndex -ServerAddresses $DomainControllerAddress
if (-not (Test-Connection -ComputerName $DomainControllerAddress -Count 2 -Quiet)) {
    throw "The domain controller at $DomainControllerAddress is not reachable."
}

$credential = Get-Credential -Message "Enter a $DomainDnsName domain administrator credential"
Add-Computer -DomainName $DomainDnsName -NewName $ComputerName -OUPath $ComputerOU -Credential $credential -Restart -Force
