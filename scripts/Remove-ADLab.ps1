#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, GroupPolicy

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot '..\config\lab-config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$domain = Get-ADDomain
if ($domain.DNSRoot -ne $config.DomainDnsName) {
    throw "Safety check failed. Connected domain '$($domain.DNSRoot)' does not match configured lab domain '$($config.DomainDnsName)'."
}

$domainDn = ($config.DomainDnsName -split '\.' | ForEach-Object { "DC=$_" }) -join ','
$rootDn = "OU=$($config.RootOUName),$domainDn"
$root = Get-ADOrganizationalUnit -Identity $rootDn -ErrorAction SilentlyContinue

if ($root -and $PSCmdlet.ShouldProcess($rootDn, 'Remove all portfolio lab users, groups, and organizational units')) {
    Get-ADUser -Filter * -SearchBase $rootDn -SearchScope Subtree | Remove-ADUser -Confirm:$false
    Get-ADGroup -Filter * -SearchBase $rootDn -SearchScope Subtree | Remove-ADGroup -Confirm:$false

    $ous = @(Get-ADOrganizationalUnit -Filter * -SearchBase $rootDn -SearchScope Subtree) |
        Sort-Object { $_.DistinguishedName.Length } -Descending
    foreach ($ou in $ous) {
        Set-ADOrganizationalUnit -Identity $ou -ProtectedFromAccidentalDeletion $false
        Remove-ADOrganizationalUnit -Identity $ou -Confirm:$false
    }
}

$gpo = Get-GPO -Name $config.Gpo.Name -ErrorAction SilentlyContinue
if ($gpo -and $PSCmdlet.ShouldProcess($config.Gpo.Name, 'Remove portfolio lab GPO')) {
    Remove-GPO -Guid $gpo.Id -Confirm:$false
}

Write-Host 'Lab cleanup complete.' -ForegroundColor Green
