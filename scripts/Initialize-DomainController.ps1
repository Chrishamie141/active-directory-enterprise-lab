#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ComputerName = 'NS-DC01',
    [string]$DomainDnsName = 'ad.northstar.test',
    [string]$DomainNetBIOSName = 'NORTHSTAR',
    [string]$IPAddress = '192.168.56.10',
    [byte]$PrefixLength = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostOnly = Get-NetAdapter | Where-Object Status -eq 'Up' | Where-Object {
    -not (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway
} | Select-Object -First 1
if (-not $hostOnly) { throw 'Could not identify the host-only network adapter (the connected adapter without a default gateway).' }

$natAdapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Where-Object {
    (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway
} | Select-Object -First 1

Get-NetIPAddress -InterfaceIndex $hostOnly.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object PrefixOrigin -ne 'WellKnown' |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $hostOnly.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $hostOnly.ifIndex -ServerAddresses '127.0.0.1'
Set-DnsClient -InterfaceIndex $hostOnly.ifIndex -RegisterThisConnectionsAddress $true
if ($natAdapter) { Set-DnsClient -InterfaceIndex $natAdapter.ifIndex -RegisterThisConnectionsAddress $false }

if ($env:COMPUTERNAME -ne $ComputerName) {
    Rename-Computer -NewName $ComputerName -Force
}

Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
$safeModePassword = Read-Host 'Enter the Directory Services Restore Mode password' -AsSecureString

Write-Host 'Promoting the server. It will reboot automatically.' -ForegroundColor Cyan
Install-ADDSForest `
    -DomainName $DomainDnsName `
    -DomainNetbiosName $DomainNetBIOSName `
    -InstallDns `
    -SafeModeAdministratorPassword $safeModePassword `
    -NoRebootOnCompletion:$false `
    -Force

