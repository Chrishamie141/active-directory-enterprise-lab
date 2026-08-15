#Requires -Version 5.1

BeforeAll {
    $script:ConfigPath = Join-Path $PSScriptRoot '..\config\lab-config.json'
    $script:Config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
}

Describe 'Lab configuration' {
    It 'contains valid JSON and required domain properties' {
        $Config.DomainDnsName | Should -Match '^[a-z0-9.-]+$'
        $Config.DomainNetBIOSName | Should -Not -BeNullOrEmpty
        $Config.RootOUName | Should -Not -BeNullOrEmpty
    }

    It 'uses unique OU keys' {
        @($Config.OrganizationalUnits.Key | Sort-Object -Unique).Count | Should -Be @($Config.OrganizationalUnits).Count
    }

    It 'defines parent OUs before their children' {
        $knownKeys = [Collections.Generic.HashSet[string]]::new()
        [void]$knownKeys.Add('domain')
        foreach ($ou in $Config.OrganizationalUnits) {
            $knownKeys.Contains([string]$ou.ParentKey) | Should -BeTrue -Because "parent '$($ou.ParentKey)' must be defined before '$($ou.Key)'"
            [void]$knownKeys.Add([string]$ou.Key)
        }
    }

    It 'uses unique user logon names' {
        @($Config.Users.SamAccountName | Sort-Object -Unique).Count | Should -Be @($Config.Users).Count
    }

    It 'only assigns users to defined groups' {
        $groupNames = @($Config.Groups.Name)
        foreach ($user in $Config.Users) {
            foreach ($group in $user.Groups) { $groupNames | Should -Contain $group }
        }
    }

    It 'only nests defined groups' {
        $groupNames = @($Config.Groups.Name)
        foreach ($pair in $Config.GroupNesting) {
            $groupNames | Should -Contain $pair.Member
            $groupNames | Should -Contain $pair.Target
        }
    }
}

