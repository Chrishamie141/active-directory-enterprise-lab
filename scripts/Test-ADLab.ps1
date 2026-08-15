#Requires -Version 5.1
#Requires -Modules ActiveDirectory, GroupPolicy

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot '..\config\lab-config.json'
}
if (-not $ReportPath) {
    $ReportPath = Join-Path $PSScriptRoot '..\reports\validation-report.html'
}

function ConvertTo-DistinguishedName {
    param([Parameter(Mandatory)][string]$DnsName)
    ($DnsName -split '\.' | ForEach-Object { "DC=$_" }) -join ','
}

function Add-Result {
    param([string]$Category, [string]$Name, [bool]$Passed, [string]$Detail)
    [pscustomobject]@{
        Category = $Category
        Check    = $Name
        Status   = if ($Passed) { 'PASS' } else { 'FAIL' }
        Detail   = $Detail
    }
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$domain = Get-ADDomain
if ($domain.DNSRoot -ne $config.DomainDnsName) {
    throw "Connected domain '$($domain.DNSRoot)' does not match configured lab domain '$($config.DomainDnsName)'."
}

$domainDn = ConvertTo-DistinguishedName -DnsName $config.DomainDnsName
$ouPaths = @{ domain = $domainDn }
$results = [Collections.Generic.List[object]]::new()

foreach ($ou in $config.OrganizationalUnits) {
    $expectedDn = "OU=$($ou.Name),$($ouPaths[$ou.ParentKey])"
    $found = Get-ADOrganizationalUnit -Identity $expectedDn -ErrorAction SilentlyContinue
    $results.Add((Add-Result -Category 'Organizational Unit' -Name $ou.Name -Passed ([bool]$found) -Detail $expectedDn))
    $ouPaths[$ou.Key] = $expectedDn
}

foreach ($group in $config.Groups) {
    $found = Get-ADGroup -Identity $group.Name -ErrorAction SilentlyContinue
    $correct = $found -and $found.GroupScope -eq $group.Scope -and $found.GroupCategory -eq $group.Category
    $results.Add((Add-Result -Category 'Group' -Name $group.Name -Passed ([bool]$correct) -Detail "Expected $($group.Scope) $($group.Category) group"))
}

foreach ($user in $config.Users) {
    $found = Get-ADUser -Identity $user.SamAccountName -Properties Department, Title, Enabled -ErrorAction SilentlyContinue
    $correct = $found -and $found.Enabled -and $found.Department -eq $user.Department -and $found.Title -eq $user.Title
    $results.Add((Add-Result -Category 'User' -Name $user.SamAccountName -Passed ([bool]$correct) -Detail "$($user.Department) / $($user.Title)"))

    foreach ($groupName in $user.Groups) {
        $membership = Get-ADGroupMember -Identity $groupName | Where-Object SamAccountName -eq $user.SamAccountName
        $results.Add((Add-Result -Category 'Membership' -Name "$($user.SamAccountName) -> $groupName" -Passed ([bool]$membership) -Detail 'Direct role-group membership'))
    }
}

foreach ($nesting in $config.GroupNesting) {
    $membership = Get-ADGroupMember -Identity $nesting.Target | Where-Object SamAccountName -eq $nesting.Member
    $results.Add((Add-Result -Category 'AGDLP Nesting' -Name "$($nesting.Member) -> $($nesting.Target)" -Passed ([bool]$membership) -Detail 'Global role group nested in domain-local resource group'))
}

$gpo = Get-GPO -Name $config.Gpo.Name -ErrorAction SilentlyContinue
$results.Add((Add-Result -Category 'Group Policy' -Name $config.Gpo.Name -Passed ([bool]$gpo) -Detail 'Workstation security baseline exists'))
if ($gpo) {
    $link = (Get-GPInheritance -Target $ouPaths['workstations']).GpoLinks | Where-Object DisplayName -eq $config.Gpo.Name
    $results.Add((Add-Result -Category 'Group Policy' -Name 'Workstation baseline link' -Passed ([bool]$link) -Detail $ouPaths['workstations']))
}

$reportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$passCount = @($results | Where-Object Status -eq 'PASS').Count
$failCount = @($results | Where-Object Status -eq 'FAIL').Count
$style = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 36px; color: #172033; }
h1 { color: #12355b; } .summary { padding: 12px; background: #eef4fa; border-left: 5px solid #2b6cb0; }
table { border-collapse: collapse; width: 100%; margin-top: 20px; } th { background: #12355b; color: white; }
th, td { border: 1px solid #d9e2ec; padding: 8px; text-align: left; } tr:nth-child(even) { background: #f7fafc; }
</style>
'@
$preContent = "<h1>$($config.ProjectName) Validation</h1><div class='summary'><strong>$passCount passed</strong> &nbsp; | &nbsp; <strong>$failCount failed</strong><br>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>"
$results | ConvertTo-Html -Title 'AD Lab Validation' -Head $style -PreContent $preContent | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$results | Format-Table -AutoSize
Write-Host "`nValidation report: $ReportPath" -ForegroundColor Cyan

if ($failCount -gt 0) { exit 1 }
