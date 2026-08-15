# Lab build guide

## Suggested environment

- A host with at least 16 GB RAM and 120 GB free storage
- Hyper-V, VMware Workstation, or VirtualBox
- One Windows Server 2022 or later VM for the domain controller
- One Windows 11 Pro/Enterprise VM for a domain-joined client
- An isolated internal virtual network; add NAT only when updates are needed

This repository assumes the forest `ad.northstar.test` already exists. On the server, assign a static IP, install AD DS and DNS, create the forest, and reboot. Take a VM snapshot before running automation.

## Deploy

Open Windows PowerShell 5.1 as a domain administrator on the domain controller:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./scripts/Deploy-ADLab.ps1 -WhatIf
./scripts/Deploy-ADLab.ps1
```

The first command previews actions. The second securely prompts for a temporary user password; the password is never stored in this repository. Re-running deployment is safe: existing objects and memberships are detected and skipped.

## Validate

```powershell
./scripts/Test-ADLab.ps1
```

The script checks the OU tree, accounts, group scopes, AGDLP nesting, GPO, and GPO link. It creates `reports/validation-report.html` and returns a nonzero exit code when a check fails.

For the client-side demonstration, join a Windows 11 VM to the domain, move its computer object into the Workstations OU, run `gpupdate /force`, and confirm policy application with:

```powershell
gpresult /h C:\Windows\Temp\northstar-gpresult.html
```

## Clean up

Review the target with `-WhatIf`, then run the cleanup command. It asks for confirmation because it removes directory objects.

```powershell
./scripts/Remove-ADLab.ps1 -WhatIf
./scripts/Remove-ADLab.ps1
```

