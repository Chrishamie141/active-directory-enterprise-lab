# Portfolio evidence checklist

Use this list to turn the build into a concise case study. Redact IP addresses, hostnames, usernames, and any data that belongs to a real environment.

## Screenshots to capture

1. Server Manager showing installed AD DS and DNS roles.
2. Active Directory Users and Computers showing the complete Northstar OU hierarchy.
3. The Groups OU showing global and domain-local security groups.
4. One user's properties showing department, title, and role-group membership.
5. A domain-local resource group showing its nested global group.
6. Group Policy Management showing the baseline linked to the Workstations OU.
7. A Windows 11 client showing domain membership and successful `gpresult` output.
8. The generated validation report with all checks passing.

## Suggested case-study narrative

**Problem:** A growing fictional financial-services company needed a maintainable identity structure with department-based administration, role-based access, and consistent workstation controls.

**Approach:** Designed an isolated Windows domain, modeled departments with OUs, implemented AGDLP group nesting, provisioned representative user accounts through idempotent PowerShell, and scoped a security baseline to workstations.

**Validation:** Used an automated test script to verify directory objects, account attributes, memberships, group nesting, and policy linkage. Confirmed client policy application with `gpresult`.

**Outcome:** Produced a reproducible lab that demonstrates Active Directory administration, PowerShell automation, least-privilege access design, Group Policy, validation, and operational cleanup.

## Resume bullet examples

- Built a reproducible Windows Active Directory lab with PowerShell, provisioning a department-based OU structure, user lifecycle data, and role-based security groups.
- Implemented the AGDLP access model and a scoped workstation Group Policy baseline to demonstrate maintainable authorization and endpoint controls.
- Created idempotent deployment, automated validation, HTML reporting, and guarded cleanup scripts for repeatable lab operations.

