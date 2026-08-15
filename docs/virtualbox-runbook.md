# VirtualBox runbook

This runbook is tailored to the detected host: VirtualBox 7.2, 15 GB RAM, 12 logical CPUs, and the existing `192.168.56.0/24` host-only network.

## 1. Finish the evaluation-media downloads

The media comes directly from the Microsoft Evaluation Center. Windows Server 2025 is a 180-day evaluation; Windows 11 Enterprise is a 90-day evaluation.

```powershell
./scripts/Get-LabStatus.ps1
./scripts/Complete-MediaDownloads.ps1
```

When both files show as ready, calculate and record their hashes:

```powershell
Get-FileHash ./media/*.iso -Algorithm SHA256
```

For a hands-off host build, `Wait-And-BuildVirtualBoxLab.ps1` can monitor the two BITS jobs, finalize them, and create both powered-off VMs. Its transcript is written to `reports/host-build.log`.

## 2. Create the virtual machines

Preview, create, and then start the server:

```powershell
./scripts/New-VirtualBoxLab.ps1 -WhatIf
./scripts/New-VirtualBoxLab.ps1 -StartDomainController
```

The script creates two dynamically expanding 80 GB disks. Each VM gets 4 GB RAM, two CPUs, a host-only lab adapter, and a NAT adapter for evaluation activation and updates. The Windows 11 VM also receives EFI and a virtual TPM 2.0.

## 3. Install Windows Server 2025

In the graphical installer, select **Windows Server 2025 Standard Evaluation (Desktop Experience)** and install to the empty disk. Choose a strong local Administrator password and install VirtualBox Guest Additions after the first login.

The repository is exposed read-only as the `NorthstarLab` shared folder. In an elevated Windows PowerShell 5.1 console inside the server, copy it locally before executing scripts:

```powershell
Copy-Item '\\VBOXSVR\NorthstarLab' 'C:\Lab' -Recurse
Set-ExecutionPolicy -Scope Process Bypass
C:\Lab\scripts\Initialize-DomainController.ps1
```

After the automatic reboot, sign in as `NORTHSTAR\Administrator` and provision the directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
C:\Lab\scripts\Deploy-ADLab.ps1 -WhatIf
C:\Lab\scripts\Deploy-ADLab.ps1
C:\Lab\scripts\Test-ADLab.ps1
```

Shut down the server cleanly, then take a checkpoint from the host. Offline checkpoints are used because they are more reliable and do not include transient guest memory:

```powershell
./scripts/Checkpoint-Lab.ps1 -Stage DomainConfigured
```

## 4. Install and join Windows 11

Start `NS-WIN11-01` in VirtualBox and install Windows 11 Enterprise Evaluation. Install Guest Additions, copy the shared project locally, and then run from elevated Windows PowerShell:

```powershell
Copy-Item '\\VBOXSVR\NorthstarLab' 'C:\Lab' -Recurse
Set-ExecutionPolicy -Scope Process Bypass
C:\Lab\scripts\Join-LabClient.ps1
```

After reboot, sign in with one of the lab accounts and verify policy:

```powershell
gpupdate /force
gpresult /h C:\Windows\Temp\northstar-gpresult.html
```

Move the computer object to `OU=Workstations,OU=Northstar` in Active Directory Users and Computers before the policy check. Then take the final checkpoint:

```powershell
./scripts/Checkpoint-Lab.ps1 -Stage ClientJoined
```

## Resource note

The two VMs reserve 8 GB combined. Close memory-heavy host applications before running both. During OS installation, run only one VM at a time. Keep the NAT adapters only for evaluation activation and updates; disable them in VirtualBox when demonstrating the isolated directory environment.
