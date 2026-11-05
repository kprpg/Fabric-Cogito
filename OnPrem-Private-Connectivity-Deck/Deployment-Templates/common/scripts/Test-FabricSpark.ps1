<#
.SYNOPSIS
  Pattern 4 end-to-end proof: creates a custom Spark pool, a notebook that reads dbo.Orders from the on-prem SQL Server
  through the managed private endpoint, runs it, and reports success/failure (the notebook asserts 5000 rows).
  Managed private endpoints require a custom pool (starter pools are not supported in such workspaces).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceId,
    [Parameter(Mandatory)][SecureString]$SqlPassword,
    [string]$SqlFqdn = 'sql01.corp.contoso.lab',
    [string]$Database = 'OnPremSalesDemo',
    [int]$ExpectedRows = 5000
)
$ErrorActionPreference = 'Stop'
$api = 'https://api.fabric.microsoft.com/v1'
$token = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv).Trim()
$h = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$pw = [System.Net.NetworkCredential]::new('', $SqlPassword).Password

function Wait-Op([string]$Location, [int]$TimeoutSec = 1500) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $r = Invoke-RestMethod -Uri $Location -Headers $h
        Write-Host "  status: $($r.status)"
        if ($r.status -in 'Completed', 'Succeeded') { return $r }
        if ($r.status -in 'Failed', 'Cancelled') { throw "Operation $($r.status): $($r.failureReason | ConvertTo-Json -Compress)" }
    }
    throw 'Timed out.'
}

Write-Host 'Creating custom Spark pool ...'
$pool = @{ name = 'pool-mpe'; nodeFamily = 'MemoryOptimized'; nodeSize = 'Small'
    autoScale = @{ enabled = $true; minNodeCount = 1; maxNodeCount = 2 }
    dynamicExecutorAllocation = @{ enabled = $true; minExecutors = 1; maxExecutors = 1 } } | ConvertTo-Json -Depth 5
$r = Invoke-WebRequest -Method Post -Uri "$api/workspaces/$WorkspaceId/spark/pools" -Headers $h -Body $pool -SkipHttpErrorCheck
if ($r.StatusCode -ge 400 -and $r.Content -notmatch 'AlreadyExists|already') { throw "Pool creation failed: $($r.Content)" }
$r = Invoke-WebRequest -Method Patch -Uri "$api/workspaces/$WorkspaceId/spark/settings" -Headers $h -SkipHttpErrorCheck `
    -Body (@{ pool = @{ defaultPool = @{ name = 'pool-mpe'; type = 'Workspace' } } } | ConvertTo-Json -Depth 5)
if ($r.StatusCode -ge 400) { throw "Setting default pool failed: $($r.Content)" }

$code = @"
url = "jdbc:sqlserver://${SqlFqdn}:1433;database=${Database};encrypt=true;trustServerCertificate=true"
df = (spark.read.format("jdbc").option("url", url).option("dbtable", "dbo.Orders")
      .option("user", "fabricsvc").option("password", "$pw")
      .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver").load())
n = df.count()
print("ORDERS_ROWCOUNT", n)
assert n == $ExpectedRows, f"unexpected row count {n}"
"@
$nb = @{ nbformat = 4; nbformat_minor = 5
    cells = @(@{ cell_type = 'code'; execution_count = $null; metadata = @{}; outputs = @(); source = @($code -split "`n" | ForEach-Object { "$_`n" }) })
    metadata = @{ language_info = @{ name = 'python' }; kernel_info = @{ name = 'synapse_pyspark' } } } | ConvertTo-Json -Depth 10
$payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nb))
$body = @{ displayName = 'nb-onprem-sql-mpe-test'; definition = @{ format = 'ipynb'; parts = @(@{ path = 'notebook-content.ipynb'; payload = $payload; payloadType = 'InlineBase64' }) } } | ConvertTo-Json -Depth 8
Write-Host 'Creating notebook ...'
$r = Invoke-WebRequest -Method Post -Uri "$api/workspaces/$WorkspaceId/notebooks" -Headers $h -Body $body -SkipHttpErrorCheck
if ($r.StatusCode -ge 400) { throw "Notebook creation failed: $($r.Content)" }
if ($r.StatusCode -eq 202) { $null = Wait-Op ($r.Headers['Location'] | Select-Object -First 1) 300 }
$items = (Invoke-RestMethod -Uri "$api/workspaces/$WorkspaceId/items?type=Notebook" -Headers $h).value
$nbId = ($items | Where-Object displayName -eq 'nb-onprem-sql-mpe-test').id

Write-Host 'Running notebook (cold Spark start takes several minutes) ...'
$r = Invoke-WebRequest -Method Post -Uri "$api/workspaces/$WorkspaceId/items/$nbId/jobs/instances?jobType=RunNotebook" -Headers $h -SkipHttpErrorCheck
if ($r.StatusCode -ne 202) { throw "Run request failed ($($r.StatusCode)): $($r.Content)" }
$res = Wait-Op ($r.Headers['Location'] | Select-Object -First 1)
Write-Host "Notebook job finished: $($res.status). Spark read $ExpectedRows rows from $SqlFqdn through the managed private endpoint." -ForegroundColor Green
