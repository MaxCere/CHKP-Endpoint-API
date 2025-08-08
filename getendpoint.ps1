param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PageSize     = 10,
    [int]   $PollInterval = 1,
    [int]   $MaxPolls     = 12,
    [string]$FilterName   = "COMPUTERNAME"
)

$scriptRelease = "GetEndpoints v3.16 (2025-08-08)"

#function Log($msg)    { Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
#function LogErr($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Log($msg)    {  }
function LogErr($msg) {  }

function ReadBody($stream) {
    try { (New-Object System.IO.StreamReader($stream)).ReadToEnd() } catch { "" }
}

# 1) Credenziali
Log "Script version: $scriptRelease"
if (-not (Test-Path $CredFile)) { LogErr "Cred file missing"; exit 1 }
$creds = Get-Content $CredFile | ConvertFrom-Json
$ClientID = $creds.clientId; $AccessKey = $creds.accessKey; $Gateway = $creds.gateway
Log "Using Gateway: $Gateway"

# 2) Auth
Log "Authenticating..."
try {
    $authResp = Invoke-RestMethod -Uri "$Gateway/auth/external" -Method Post `
        -Body (@{clientId=$ClientID;accessKey=$AccessKey}|ConvertTo-Json) `
        -ContentType 'application/json' -ErrorAction Stop
    $token = $authResp.data.token
    Log "Token length=$($token.Length) [masked]"
} catch {
    LogErr "Authentication failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
    exit 1
}

# 3) Cloud login
Log "Cloud login..."
try {
    $loginResp = Invoke-WebRequest -Uri "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud" `
        -Method Post -Headers @{Authorization="Bearer $token"} `
        -Body '{}' -ContentType 'application/json' -ErrorAction Stop
    $mgmtToken = $loginResp.Headers['x-mgmt-api-token']
    Log "Mgmt token length=$($mgmtToken.Length) [masked]"
} catch {
    LogErr "Cloud login failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
    exit 1
}

# 4) Creo job
Log "4) Creo job ComputersByFilter"
$filterUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/asset-management/computers/filtered"
$jobHeaders = @{
    Authorization       = "Bearer ***MASKED***"
    "x-mgmt-api-token"  = "***MASKED***"
    "x-mgmt-run-as-job" = "on"
}
$jobBodyObj = @{
    filters = @(
        @{
            columnName   = "computerName"
            filterValues = @($FilterName)
            filterType   = "Contains"
        }
    )
    paging = @{ pageSize = $PageSize; offset = 0 }
}
$jobBody = $jobBodyObj | ConvertTo-Json -Depth 4
Log "   Gateway: $filterUrl"
Log "   Headers (masked): $(ConvertTo-Json $jobHeaders -Depth 3)"
Log "   Body: $jobBody"

try {
    $r = Invoke-WebRequest -Uri $filterUrl -Method Post `
        -Headers @{
            Authorization       = "Bearer $token"
            "x-mgmt-api-token"  = $mgmtToken
            "x-mgmt-run-as-job" = "on"
        } `
        -Body $jobBody -ContentType "application/json" -ErrorAction Stop

    Log "   HTTP status create-job: $($r.StatusCode.value__)"
    Log "   Response headers: $(ConvertTo-Json $r.Headers -Depth 3)"
    Log "   Response content: $($r.Content)"
} catch {
    LogErr "Job creation failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
    exit 1
}

$jobJson = $r.Content | ConvertFrom-Json
$jobId   = $jobJson.jobId
Log "   Job ID: $jobId"
if (-not $jobId) { LogErr "jobId not found in response."; exit 1 }

# 5) Polling job
Log "5) Polling job"
$jobUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/$jobId"
$pollHeaders = @{
    Authorization      = "***MASKED***"
    "x-mgmt-api-token" = "***MASKED***"
}
Log "   Polling URL: $jobUrl"
Log "   Headers (masked): $(ConvertTo-Json $pollHeaders -Depth 3)"

$attempt = 0
do {
    Start-Sleep -Seconds $PollInterval
    $attempt++
    Log "   Polling attempt #$attempt..."
    try {
        $resp = Invoke-WebRequest -Uri $jobUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        $json = $resp.Content | ConvertFrom-Json
        $status = $json.status
        Log "   Stato job: '$status'"
        Log "   Computers[]: $(ConvertTo-Json $json.data.computers -Depth 4)"
    } catch {
        LogErr "Polling failed: $($_.Exception.Message)"
        if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
        exit 1
    }
} until ($status -eq "DONE" -or $attempt -ge $MaxPolls)

if ($status -ne "DONE") {
    LogErr "Job did not complete within $MaxPolls attempts."
    exit 1
}

# 6) Output
$items = $json.data.computers
if (-not $items) { LogErr "No computers in job response"; exit 1 }

Log "6) Endpoints found: $($items.Count)"
$items | ForEach-Object {
    [PSCustomObject]@{
        EndpointID      = $_.computerId
        Hostname        = $_.computerName
        IP              = $_.computerIP
        IsolationStatus = $_.isolationStatus
        Groups          = ($_.computerGroups.name -join ", ")
    }
} | Format-Table -AutoSize

Log "=== FINE SCRIPT - $scriptRelease ==="

