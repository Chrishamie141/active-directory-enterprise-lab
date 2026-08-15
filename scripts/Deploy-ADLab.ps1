#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, GroupPolicy

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [Security.SecureString]$InitialPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot '..\config\lab-config.json'
}

function ConvertTo-DistinguishedName {
    param([Parameter(Mandatory)][string]$DnsName)
    ($DnsName -split '\.' | ForEach-Object { "DC=$_" }) -join ','
}

function Assert-LabDomain {
    param([Parameter(Mandatory)]$Config)

    $domain = Get-ADDomain
    if ($domain.DNSRoot -ne $Config.DomainDnsName) {
        throw "Safety check failed. Connected domain '$($domain.DNSRoot)' does not match configured lab domain '$($Config.DomainDnsName)'."
    }
}

function Ensure-OrganizationalUnit {
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$ParentPath
    )

    $existing = Get-ADOrganizationalUnit -LDAPFilter "(ou=$($Definition.Name))" -SearchBase $ParentPath -SearchScope OneLevel -ErrorAction SilentlyContinue
    if ($existing) { return $existing }

    if ($PSCmdlet.ShouldProcess("OU=$($Definition.Name),$ParentPath", 'Create organizational unit')) {
        return New-ADOrganizationalUnit -Name $Definition.Name -Path $ParentPath -Description $Definition.Description -ProtectedFromAccidentalDeletion $true -PassThru
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Assert-LabDomain -Config $config
$domainDn = ConvertTo-DistinguishedName -DnsName $config.DomainDnsName

if (-not $InitialPassword) {
    if ($WhatIfPreference) {
        # New-ADUser is not invoked during a preview, but its parameter still needs a value.
        $previewOnlyValue = '{0}!Aa1' -f ([guid]::NewGuid().Guid)
        $InitialPassword = ConvertTo-SecureString $previewOnlyValue -AsPlainText -Force
    }
    else {
        $InitialPassword = Read-Host 'Enter a temporary password for the lab users' -AsSecureString
    }
}

Write-Host "Deploying $($config.ProjectName) to $($config.DomainDnsName)..." -ForegroundColor Cyan

$ouPaths = @{ domain = $domainDn }
foreach ($ou in $config.OrganizationalUnits) {
    if (-not $ouPaths.ContainsKey($ou.ParentKey)) {
        throw "OU '$($ou.Key)' references unknown or not-yet-created parent '$($ou.ParentKey)'."
    }

    $createdOu = Ensure-OrganizationalUnit -Definition $ou -ParentPath $ouPaths[$ou.ParentKey]
    $ouPaths[$ou.Key] = if ($createdOu) { $createdOu.DistinguishedName } else { "OU=$($ou.Name),$($ouPaths[$ou.ParentKey])" }
}

foreach ($group in $config.Groups) {
    $existing = Get-ADGroup -Filter "SamAccountName -eq '$($group.Name)'" -ErrorAction SilentlyContinue
    if (-not $existing -and $PSCmdlet.ShouldProcess($group.Name, 'Create security group')) {
        New-ADGroup -Name $group.Name -SamAccountName $group.Name -GroupScope $group.Scope -GroupCategory $group.Category -Path $ouPaths[$group.OUKey] -Description $group.Description | Out-Null
    }
}

foreach ($user in $config.Users) {
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue
    $displayName = "$($user.GivenName) $($user.Surname)"
    if (-not $existing -and $PSCmdlet.ShouldProcess($user.SamAccountName, 'Create lab user')) {
        New-ADUser -Name $displayName `
            -SamAccountName $user.SamAccountName `
            -UserPrincipalName "$($user.SamAccountName)@$($config.DomainDnsName)" `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -DisplayName $displayName `
            -Department $user.Department `
            -Title $user.Title `
            -Path $ouPaths[$user.OUKey] `
            -AccountPassword $InitialPassword `
            -Enabled $true `
            -ChangePasswordAtLogon $true
    }
    elseif ($existing -and $PSCmdlet.ShouldProcess($user.SamAccountName, 'Repair lab user attributes and account state')) {
        Set-ADUser -Identity $existing `
            -UserPrincipalName "$($user.SamAccountName)@$($config.DomainDnsName)" `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -DisplayName $displayName `
            -Department $user.Department `
            -Title $user.Title

        if (-not $existing.Enabled) {
            Set-ADAccountPassword -Identity $existing -Reset -NewPassword $InitialPassword
            Enable-ADAccount -Identity $existing
            Set-ADUser -Identity $existing -ChangePasswordAtLogon $true
        }
    }

    foreach ($groupName in $user.Groups) {
        $isMember = Get-ADGroupMember -Identity $groupName | Where-Object SamAccountName -eq $user.SamAccountName
        if (-not $isMember -and $PSCmdlet.ShouldProcess("$($user.SamAccountName) -> $groupName", 'Add group membership')) {
            Add-ADGroupMember -Identity $groupName -Members $user.SamAccountName
        }
    }
}

foreach ($nesting in $config.GroupNesting) {
    $isMember = Get-ADGroupMember -Identity $nesting.Target | Where-Object SamAccountName -eq $nesting.Member
    if (-not $isMember -and $PSCmdlet.ShouldProcess("$($nesting.Member) -> $($nesting.Target)", 'Nest group')) {
        Add-ADGroupMember -Identity $nesting.Target -Members $nesting.Member
    }
}

$gpo = Get-GPO -Name $config.Gpo.Name -ErrorAction SilentlyContinue
if (-not $gpo -and $PSCmdlet.ShouldProcess($config.Gpo.Name, 'Create workstation baseline GPO')) {
    $gpo = New-GPO -Name $config.Gpo.Name -Comment 'Portfolio lab baseline. Review settings before production use.'
}

if ($gpo) {
    foreach ($setting in $config.Gpo.Settings) {
        if ($PSCmdlet.ShouldProcess("$($config.Gpo.Name): $($setting.ValueName)", 'Configure registry policy')) {
            Set-GPRegistryValue -Name $config.Gpo.Name -Key $setting.Key -ValueName $setting.ValueName -Type $setting.Type -Value $setting.Value | Out-Null
        }
    }

    $workstationOu = $ouPaths['workstations']
    $link = (Get-GPInheritance -Target $workstationOu).GpoLinks | Where-Object DisplayName -eq $config.Gpo.Name
    if (-not $link -and $PSCmdlet.ShouldProcess($workstationOu, "Link GPO '$($config.Gpo.Name)'")) {
        New-GPLink -Name $config.Gpo.Name -Target $workstationOu -LinkEnabled Yes | Out-Null
    }
}

Write-Host 'Deployment complete. Run Test-ADLab.ps1 to validate the result.' -ForegroundColor Green
