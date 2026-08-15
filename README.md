# Northstar Financial Active Directory Lab

A portfolio-ready Windows Server lab that demonstrates Active Directory design, PowerShell automation, role-based access, Group Policy, validation, and safe cleanup for a fictional financial-services organization.

**Live repository:** [github.com/Chrishamie141/active-directory-enterprise-lab](https://github.com/Chrishamie141/active-directory-enterprise-lab)

**Project announcement:** [View the LinkedIn post](https://www.linkedin.com/feed/update/urn:li:share:7494541719796068352/)

> This project is designed for an isolated lab domain. Do not run it against a production or employer-managed directory.

## What this project demonstrates

- Department-based organizational unit design
- Six representative user accounts with business attributes
- Global and domain-local security groups using the AGDLP access model
- A scoped workstation security-baseline GPO
- Idempotent PowerShell deployment with `-WhatIf` support
- Automated validation with an HTML report
- Guarded cleanup with exact-domain safety checks

## Architecture

```text
ad.northstar.test
└── Northstar
    ├── Admins
    ├── Groups
    ├── Servers
    ├── Workstations  ← workstation baseline GPO
    └── Users
        ├── Finance
        ├── Human Resources
        └── Information Technology
```

Accounts are placed into global role groups, which are nested inside domain-local resource groups. This separates a person's business role from the permissions assigned to a resource.

## Quick start

Prerequisites are a disposable Windows Server domain controller for `ad.northstar.test`, Windows PowerShell 5.1, and the ActiveDirectory and GroupPolicy modules.

```powershell
# Preview first
./scripts/Deploy-ADLab.ps1 -WhatIf

# Deploy and securely enter the temporary account password
./scripts/Deploy-ADLab.ps1

# Validate and generate reports/validation-report.html
./scripts/Test-ADLab.ps1
```

Start with the [build guide](docs/build-guide.md), then review the [architecture decisions](docs/architecture.md) and [portfolio evidence checklist](docs/portfolio-evidence.md).

Using VirtualBox? Follow the host-specific [VirtualBox runbook](docs/virtualbox-runbook.md). It covers media preparation, VM creation, domain promotion, client joining, and checkpoints.

## Completed lab evidence

The reference build was validated in VirtualBox with Windows Server 2025 and Windows 11 Enterprise Evaluation:

- `NS-DC01` hosts `ad.northstar.test`; the automated directory validation completed with 32 passes and 0 failures.
- `NS-WIN11-01` is domain joined, uses `192.168.56.10` for lab DNS, and resides in the Northstar Workstations OU.
- The `Northstar - Workstation Security Baseline` GPO applies to the client, including a verified 900-second inactivity timeout.
- Offline recovery points are saved as `LabComplete` on the domain controller and `DomainJoined` on the client.

See [the directory validation report](reports/validation-report.html), [the client validation summary](reports/client-validation.txt), and [the applied-policy evidence](reports/client-gpresult-final.png).

## Repository layout

| Path | Purpose |
|---|---|
| `config/lab-config.json` | Domain objects, relationships, and example policy settings |
| `scripts/Deploy-ADLab.ps1` | Idempotent provisioning and GPO configuration |
| `scripts/Test-ADLab.ps1` | Validation and HTML reporting |
| `scripts/Remove-ADLab.ps1` | Confirmation-protected lab cleanup |
| `scripts/New-VirtualBoxLab.ps1` | Creates the server and client VMs with isolated and NAT networking |
| `scripts/Initialize-DomainController.ps1` | Configures networking and promotes Windows Server |
| `scripts/Join-LabClient.ps1` | Points the client to AD DNS and joins the domain |
| `tests/Config.Tests.ps1` | Pester tests for configuration integrity |
| `docs/` | Architecture, build instructions, and case-study guidance |

## Testing without a domain

The configuration tests require Pester 5 but do not require Active Directory:

```powershell
Invoke-Pester ./tests/Config.Tests.ps1
```

The deployment and validation scripts must run on a machine that can reach the configured lab domain. Each state-changing script refuses to proceed when the connected domain name does not exactly match the configuration.

## Future enhancements

- Add a second domain controller and test replication and DNS failover.
- Build a file server and apply NTFS/share permissions to the domain-local groups.
- Add Windows LAPS, privileged account separation, and fine-grained password policies.
- Forward security events to a SIEM and document detection use cases.
- Convert the lab build to DSC or an image-based pipeline.

## License

MIT
