# Stage 2 - runs as SYSTEM at boot (scheduled by Stage 1). Idempotent: re-run with
#   Start-ScheduledTask -TaskName OnPremSim-Stage2
# NOTE: this file is embedded in Stage 1 inside a single-quoted here-string; never start a line with '@
$ErrorActionPreference = 'Stop'
$root = 'C:\OnPremSim'
$state = "$root\state"
New-Item -ItemType Directory -Path $state -Force | Out-Null
Start-Transcript -Path "$root\stage2.log" -Append | Out-Null

function Step([string]$m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format s), $m) }
function Done([string]$n) { Test-Path "$state\$n" }
function Mark([string]$n) { New-Item -ItemType File -Path "$state\$n" -Force | Out-Null }

function Invoke-Sql([string]$Query, [string]$Database = 'master', [string]$App = 'OnPremSim') {
    $cn = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Database=$Database;Integrated Security=SSPI;TrustServerCertificate=True;Connect Timeout=30;Application Name=$App"
    $cn.Open()
    try {
        foreach ($batch in ($Query -split '(?im)^\s*GO\s*$')) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $cmd = $cn.CreateCommand(); $cmd.CommandTimeout = 300; $cmd.CommandText = $batch
            [void]$cmd.ExecuteNonQuery()
        }
    } finally { $cn.Close() }
}

function Test-SqlSysadmin {
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection 'Server=localhost;Database=master;Integrated Security=SSPI;TrustServerCertificate=True;Connect Timeout=15'
        $cn.Open(); $cmd = $cn.CreateCommand(); $cmd.CommandText = "SELECT IS_SRVROLEMEMBER('sysadmin')"
        $r = $cmd.ExecuteScalar(); $cn.Close(); return ($r -eq 1)
    } catch { return $false }
}

function Grant-SystemSysadmin {
    # The marketplace image does not make NT AUTHORITY\SYSTEM a sysadmin. In single-user mode local
    # administrators are sysadmin, which lets us grant it and continue unattended.
    Step 'Granting NT AUTHORITY\SYSTEM sysadmin via single-user mode'
    Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue
    Stop-Service MSSQLSERVER -Force
    & net.exe start MSSQLSERVER /mSQLCMD | Out-Null
    $done = $false
    for ($i = 0; $i -lt 12 -and -not $done; $i++) {
        try {
            Invoke-Sql "IF SUSER_ID(N'NT AUTHORITY\SYSTEM') IS NULL CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM];" 'master' 'SQLCMD'
            $done = $true
        } catch { Start-Sleep -Seconds 5 }
    }
    Stop-Service MSSQLSERVER -Force
    Start-Service MSSQLSERVER
    Start-Service SQLSERVERAGENT -ErrorAction SilentlyContinue
    if (-not $done) { throw 'Could not grant sysadmin in single-user mode.' }
}

function Get-ImdsContext {
    # Reads Azure metadata + managed-identity token. Temporarily lifts the IMDS block if it is already in place.
    $rule = Get-NetFirewallRule -Name 'BlockAzureIMDS' -ErrorAction SilentlyContinue
    if ($rule) { Disable-NetFirewallRule -Name 'BlockAzureIMDS' }
    try {
        $h = @{ Metadata = 'true' }
        $compute = Invoke-RestMethod -Headers $h -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' -TimeoutSec 20
        $tok = Invoke-RestMethod -Headers $h -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -TimeoutSec 20
        $payload = $tok.access_token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        while ($payload.Length % 4) { $payload += '=' }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        [pscustomobject]@{
            SubscriptionId = $compute.subscriptionId
            ResourceGroup  = $compute.resourceGroupName
            Location       = $compute.location
            TenantId       = $claims.tid
            Token          = $tok.access_token
        }
    } finally { if ($rule) { Enable-NetFirewallRule -Name 'BlockAzureIMDS' } }
}

$cfg = Get-Content "$root\config.json" -Raw | ConvertFrom-Json

try {
    # 1. Data disk for Hyper-V VMs ------------------------------------------------------------
    if ($cfg.installHyperV -and -not (Done 'disk')) {
        Step 'Initialising data disk as F:'
        $raw = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
        if ($raw) {
            $raw | Initialize-Disk -PartitionStyle GPT -PassThru |
                New-Partition -DriveLetter F -UseMaximumSize |
                Format-Volume -FileSystem NTFS -NewFileSystemLabel 'HyperV' -Confirm:$false | Out-Null
        }
        New-Item -ItemType Directory -Path 'F:\Hyper-V\Disks' -Force | Out-Null
        Mark 'disk'
    }

    # 2. Hyper-V internal "on-prem LAN" switch + routing --------------------------------------
    if ($cfg.installHyperV -and -not (Done 'hyperv')) {
        Step 'Configuring Hyper-V host'
        Import-Module Hyper-V
        Set-VMHost -VirtualMachinePath 'F:\Hyper-V' -VirtualHardDiskPath 'F:\Hyper-V\Disks'
        if (-not (Get-VMSwitch -Name 'vsw-onprem-lan' -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name 'vsw-onprem-lan' -SwitchType Internal | Out-Null
        }
        $prefixLen = [int]($cfg.nestedLanPrefix.Split('/')[1])
        $alias = 'vEthernet (vsw-onprem-lan)'
        if (-not (Get-NetIPAddress -InterfaceAlias $alias -IPAddress $cfg.nestedLanGatewayIp -ErrorAction SilentlyContinue)) {
            New-NetIPAddress -InterfaceAlias $alias -IPAddress $cfg.nestedLanGatewayIp -PrefixLength $prefixLen | Out-Null
        }
        Get-NetIPInterface -AddressFamily IPv4 | Set-NetIPInterface -Forwarding Enabled
        Mark 'hyperv'
    }

    # 3. Windows Firewall + DNS ---------------------------------------------------------------
    if (-not (Done 'firewall')) {
        Step 'Opening SQL / DNS / ICMP'
        New-NetFirewallRule -Name 'OnPremSim-SQL' -DisplayName 'OnPremSim SQL 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name 'OnPremSim-DNS-UDP' -DisplayName 'OnPremSim DNS UDP' -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name 'OnPremSim-DNS-TCP' -DisplayName 'OnPremSim DNS TCP' -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -ErrorAction SilentlyContinue
        Mark 'firewall'
    }

    if ($cfg.dnsZone -and -not (Done 'dns')) {
        Step "Creating DNS zone $($cfg.dnsZone)"
        if (-not (Get-DnsServerZone -Name $cfg.dnsZone -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $cfg.dnsZone -ZoneFile "$($cfg.dnsZone).dns"
        }
        Add-DnsServerResourceRecordA -ZoneName $cfg.dnsZone -Name $cfg.dnsRecord -IPv4Address $cfg.hostIp -ErrorAction SilentlyContinue
        Set-DnsServerForwarder -IPAddress 168.63.129.16
        Mark 'dns'
    }

    # 4. SQL Server: mixed mode, sample database, read-only login for Fabric ------------------
    if ($cfg.installSql -and -not (Done 'sql')) {
        Step 'Configuring SQL Server'
        $inst = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').MSSQLSERVER
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$inst\MSSQLServer" -Name LoginMode -Value 2
        Restart-Service MSSQLSERVER -Force
        $ok = $false
        for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
            try { Invoke-Sql 'SELECT 1'; $ok = $true } catch { Start-Sleep -Seconds 10 }
        }
        if (-not $ok) { throw 'SQL Server did not become reachable with Windows authentication as SYSTEM.' }
        if (-not (Test-SqlSysadmin)) { Grant-SystemSysadmin; Start-Sleep -Seconds 10 }
        if (-not (Test-SqlSysadmin)) { throw 'SYSTEM is still not sysadmin.' }

        $sqlPwd = $cfg.sqlPassword.Replace("'", "''")
        $login = $cfg.sqlLogin
        Invoke-Sql "IF DB_ID('OnPremSalesDemo') IS NULL CREATE DATABASE OnPremSalesDemo;"
        Invoke-Sql "IF SUSER_ID('$login') IS NULL CREATE LOGIN [$login] WITH PASSWORD = N'$sqlPwd', CHECK_POLICY = OFF;"
        $seed = @"
IF OBJECT_ID('dbo.Customers') IS NULL
BEGIN
  CREATE TABLE dbo.Customers (CustomerId INT NOT NULL PRIMARY KEY, Name NVARCHAR(100) NOT NULL, City NVARCHAR(60) NOT NULL, Segment NVARCHAR(30) NOT NULL);
  INSERT dbo.Customers
  SELECT TOP (500) n, CONCAT(N'Customer ', n), CHOOSE(n % 5 + 1, N'Seattle', N'Chicago', N'Dallas', N'Atlanta', N'Denver'), CHOOSE(n % 3 + 1, N'Retail', N'Enterprise', N'SMB')
  FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;
END
GO
IF OBJECT_ID('dbo.Orders') IS NULL
BEGIN
  CREATE TABLE dbo.Orders (OrderId INT NOT NULL PRIMARY KEY, CustomerId INT NOT NULL REFERENCES dbo.Customers(CustomerId), OrderDate DATE NOT NULL, Amount DECIMAL(10,2) NOT NULL);
  INSERT dbo.Orders
  SELECT TOP (5000) n, n % 500 + 1, DATEADD(DAY, -(n % 365), CAST(SYSUTCDATETIME() AS DATE)), CAST((n * 37 % 9900) / 10.0 + 5 AS DECIMAL(10,2))
  FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;
END
GO
IF USER_ID('$login') IS NULL CREATE USER [$login] FOR LOGIN [$login];
ALTER ROLE db_datareader ADD MEMBER [$login];
"@
        Invoke-Sql $seed 'OnPremSalesDemo'
        Mark 'sql'
    }

    # 5. Present as a NON-Azure server (IMDS block + guest agent off) and onboard to Azure Arc ---
    if ($cfg.presentAsNonAzure -and -not (Done 'nonazure')) {
        Step 'Capturing Azure identity before IMDS is blocked'
        $ctx = $null
        for ($i = 0; $i -lt 10 -and -not $ctx; $i++) {
            try { $ctx = Get-ImdsContext } catch { Start-Sleep -Seconds 15 }
        }
        if ($cfg.onboardArc -and -not $ctx) { throw 'Could not obtain Azure metadata from IMDS.' }
        if ($ctx -and $cfg.arcAccessToken) { $ctx.Token = $cfg.arcAccessToken }

        Step 'Setting MSFT_ARC_TEST, disabling Azure VM guest agent, blocking IMDS'
        [Environment]::SetEnvironmentVariable('MSFT_ARC_TEST', 'true', [EnvironmentVariableTarget]::Machine)
        $env:MSFT_ARC_TEST = 'true'
        if (Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue) {
            Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
            Stop-Service WindowsAzureGuestAgent -Force -Verbose
        }
        New-NetFirewallRule -Name 'BlockAzureIMDS' -DisplayName 'Block access to Azure IMDS' -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254 -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name 'BlockAzureLocalIMDS' -DisplayName 'Block access to Azure Local IMDS' -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.253 -ErrorAction SilentlyContinue | Out-Null

        if ($cfg.onboardArc) {
            Step 'Installing Azure Connected Machine agent'
            $installer = Join-Path $env:TEMP 'install_windows_azcmagent.ps1'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://gbl.his.arc.azure.com/azcmagent-windows' -TimeoutSec 60 -OutFile $installer
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
            $azcm = Join-Path $env:ProgramW6432 'AzureConnectedMachineAgent\azcmagent.exe'
            if (-not (Test-Path $azcm)) { throw 'azcmagent.exe not found after install (did the installer detect an Azure VM?).' }

            $connected = $false
            for ($i = 0; $i -lt 8 -and -not $connected; $i++) {
                Step "azcmagent connect (attempt $($i + 1))"
                & $azcm connect --resource-group $ctx.ResourceGroup --tenant-id $ctx.TenantId --location $ctx.Location `
                    --subscription-id $ctx.SubscriptionId --resource-name $cfg.arcResourceName --access-token $ctx.Token `
                    --tags $cfg.arcTags
                if ($LASTEXITCODE -eq 0) { $connected = $true } else { Start-Sleep -Seconds 90 }  # RBAC propagation
            }
            if (-not $connected) { throw 'azcmagent connect failed after retries.' }
        }
        Mark 'nonazure'
    }

    Step 'Stage 2 complete'
    Mark 'complete'
    Remove-Item "$root\config.json" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path "$root\stage2.done" -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'OnPremSim-Stage2' -Confirm:$false -ErrorAction SilentlyContinue
}
catch {
    Write-Host "STAGE 2 FAILED: $_"
    Write-Host $_.ScriptStackTrace
    throw
}
finally {
    Stop-Transcript | Out-Null
}
