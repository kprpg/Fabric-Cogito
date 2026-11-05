# 04 - Simulating on-premises: a nested-Hyper-V host that looks non-Azure, and the VPN peer

## The "on-prem" asset

`common/modules/onprem-host.bicep` deploys a Windows Server 2022 VM on `Standard_D4s_v5` (Dsv5 supports nested
virtualization) from the *SQL Server 2022 Developer on WS2022* marketplace image (Pattern 3 gateway nodes use plain WS2022).
Bootstrap is two-stage because the last step disables the Azure guest agent that would otherwise be running it:

| Stage | Runs as | What it does |
|---|---|---|
| 1 - Run Command (ARM) | guest agent | stages `C:\OnPremSim\Stage2.ps1` + `config.json` (ACL: SYSTEM/Administrators), installs Hyper-V + DNS roles, registers a startup scheduled task, reboots |
| 2 - startup task | SYSTEM, after reboot | data disk `F:` for VMs; internal vSwitch `vsw-onprem-lan` (10.N0.2.0/24, host `.2.1`) with IP forwarding; Windows Firewall for 1433/53/ICMP; DNS zone `corp.contoso.lab` (`sql01` -> host IP, forwarder 168.63.129.16); SQL mixed mode, database `OnPremSalesDemo` (Customers 500 rows, Orders 5000), read-only login `fabricsvc`; then the non-Azure steps below |

Log: `C:\OnPremSim\stage2.log`. Re-run (idempotent): `Start-ScheduledTask OnPremSim-Stage2`.

### Presenting as a non-Azure server (Microsoft Learn: *Evaluate Azure Arc-enabled servers on an Azure VM*)

Stage 2 performs, in order:

1. Read subscription/RG/location and an ARM token while IMDS is still reachable (managed identity, or the deployer's token when
   no role-assignment rights - see below).
2. `MSFT_ARC_TEST=true` (machine scope) so the Arc installer accepts an Azure VM.
3. `WindowsAzureGuestAgent`: `Set-Service ... -StartupType Disabled`, `Stop-Service -Force`.
4. Firewall rules blocking outbound `169.254.169.254` (`BlockAzureIMDS`) and `169.254.169.253` (`BlockAzureLocalIMDS`).
5. Install the Connected Machine agent and `azcmagent connect --access-token ...` (retries for RBAC propagation).

Result: the same machine shows twice in Azure - `Microsoft.Compute/virtualMachines` `vm-...-sql01-...` (virtual hardware)
and `Microsoft.HybridCompute/machines` `vm-...-sql01-...-arc` (guest OS, extensions, Policy). Caveats: Azure VM extensions
stop working (the bootstrap Run Command remains listed), the VM cannot be re-deployed with a new bootstrap (the deploy script
sets `runBootstrap=false` automatically when VMs exist), and Microsoft supports this for evaluation only.

**Arc onboarding without Owner:** the template grants the VM identity *Azure Connected Machine Onboarding* on its RG. If the
deployer cannot create role assignments, `Deploy-Pattern.ps1`/`Initialize-AzdEnv.ps1` pass the deployer's ARM token instead
(valid roughly an hour, enough for the first boot). `-NoArc` skips onboarding; IMDS stays blocked either way.

### Nested guests

`New-NestedGuest.ps1` (run on the host) creates a Gen2 guest from a VHDX you supply on `vsw-onprem-lan`. Give it a static IP in
10.N0.2.0/24 with gateway 10.N0.2.1. To reach it from Azure add a route table on `GatewaySubnet` (on-prem VNet) with
`10.N0.2.0/24 -> VirtualAppliance <host .1.4>`; the host NIC already has IP forwarding enabled. The default lab keeps SQL on the
host itself because that needs no external image.

## What the VPN connects to

Patterns 1, 2, 4 build a real IKEv2/IPsec tunnel with BGP between two Azure VPN gateways:

```
Azure VNet(s) --[VpnGw1AZ, ASN 650x0]==== IPsec/IKEv2 + BGP ====[VpnGw1AZ, ASN 651x0]-- "on-prem" VNet 10.1x0.0.0/16
                                                                                         \_ snet-lan: SQL/Hyper-V host (non-Azure looking)
```

The second gateway *is the customer edge device*: each side has a local network gateway describing the other, a shared key
(Key Vault `vpn-shared-key`), BGP peering on the gateways' APIPA-free default BGP IPs. Because the tunnel runs over public
IPs it behaves like the internet path in Pattern 2. A Linux strongSwan VM or Windows RRAS host can replace the second gateway
if you need to demo a third-party device; the Azure side stays unchanged.

NSG on `snet-lan`: allow 1433/53/ICMP from the Azure-side prefixes, RDP from `VirtualNetwork` (Bastion Developer), deny the rest.
Outbound uses a NAT gateway (default outbound access is retired for new VNets).
