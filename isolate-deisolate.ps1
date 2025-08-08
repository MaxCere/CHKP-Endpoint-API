param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PageSize     = 10,
    [int]   $PollInterval = 1,
    [int]   $MaxPolls     = 12,
    [string]$FilterName   = "Win11-LAB"
)

$scriptRelease = "GetEndpoints v3.25 (2025-08-07)"

function Log($msg) {
    Write-Host "[DEBUG] $msg" -ForegroundColor Cyan
}

function LogErr($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function ReadBody($stream) {
    try { (New-Object System.IO.StreamReader($stream)).ReadToEnd() } catch { "" }
}

# Start
Log "Script version: $scriptRelease"

# Load credentials
if (-not (Test-Path $CredFile)) {
    LogErr "Cred file missing: $CredFile"
    exit 1
}
$creds     = Get-Content $CredFile | ConvertFrom-Json
$ClientID  = $creds.clientId
$AccessKey = $creds.accessKey
$Gateway   = $creds.gateway
$BasePath  = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api"

# Authenticate
Log "Authenticating with Infinity Portal..."
try {
    $authUrl  = "$Gateway/auth/external"
    $authBody = @{ clientId = $ClientID; accessKey = $AccessKey } | ConvertTo-Json
    $authResp = Invoke-RestMethod -Uri $authUrl -Method Post -Body $authBody -ContentType 'application/json' -ErrorAction Stop
    $token    = $authResp.data.token
    Log "Token obtained (length $($token.Length))"
} catch {
    LogErr "Authentication failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
    exit 1
}

# Cloud login for mgmt token
Log "Performing cloud login..."
try {
    $loginUrl  = "$BasePath/v1/session/login/cloud"
    $loginResp = Invoke-WebRequest -Uri $loginUrl -Method Post -Headers @{ Authorization = "Bearer $token" } -Body '{}' -ContentType 'application/json' -ErrorAction Stop
    $mgmtToken = $loginResp.Headers['x-mgmt-api-token']
    Log "Mgmt token obtained (length $($mgmtToken.Length))"
} catch {
    LogErr "Cloud login failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
    exit 1
}

# Function: Retrieve endpoints
function Get-Endpoints {
    param([string]$Label)
    Log "Retrieving endpoints: $Label"
    $url      = "$BasePath/v1/asset-management/computers/filtered"
    $bodyObj  = @{ filters = @(@{ columnName='computerName'; filterValues=@($FilterName); filterType='Contains' }); paging = @{ pageSize=$PageSize; offset=0 } }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5

    # Submit job
    $jobResp = Invoke-RestMethod -Uri $url -Method Post -Headers @{ Authorization = "Bearer $token"; 'x-mgmt-api-token' = $mgmtToken; 'x-mgmt-run-as-job' = 'on' } -Body $bodyJson -ContentType 'application/json'
    $jobId   = $jobResp.jobId
    Log "Asset job submitted: $jobId"

    # Poll job status
    $statusUrl = "$BasePath/v1/jobs/$jobId"
    $attempt   = 0
    do {
        Start-Sleep -Seconds $PollInterval
        $attempt++
        try {
            $statResp = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers @{ Authorization = "Bearer $token"; 'x-mgmt-api-token' = $mgmtToken }
            Log "Polling asset job ($attempt/$MaxPolls): $($statResp.status)"
        } catch {
            if ($_.Exception.Response) {
                $code = $_.Exception.Response.StatusCode.Value__
                if ($code -eq 404) {
                    LogErr "Asset job not found, retrying..."
                    continue
                } elseif ($code -eq 429) {
                    LogErr "Rate limited polling endpoints, backing off..."
                    Start-Sleep -Seconds ($PollInterval * 5)
                    continue
                }
            }
            throw
        }
    } until ($statResp.status -eq 'DONE' -or $attempt -ge $MaxPolls)

    if ($statResp.status -ne 'DONE') {
        LogErr "Asset job did not complete: $($statResp.status)"
        exit 1
    }

    return $statResp.data.computers | ForEach-Object {
        [PSCustomObject]@{
            ID        = $_.computerId
            Name      = $_.computerName
            IP        = $_.computerIP
            Status    = $_.status
            Isolation = $_.isolationStatus
        }
    }
}

# Function: Toggle isolation
function Invoke-Remediation {
    param([PSCustomObject]$Endpoint)

    $action  = if ($Endpoint.Isolation -eq 'Not Isolated') { 'isolate' } else { 'de-isolate' }
    Log "Invoking remediation '$action' on '$($Endpoint.Name)'"
    $url     = "$BasePath/v1/remediation/$action"
    $headers = @{ Authorization = "Bearer $token"; 'x-mgmt-api-token' = $mgmtToken; 'x-mgmt-run-as-job' = 'on' }

    $comment = if ($action -eq 'isolate') { 'Isolate via script' } else { 'De-isolate via script' }
    $targets = @{ 
        query   = @{ 
            filter = @(@{ columnName='emonJsonDataColumns'; filterValues=@('string'); filterType='Contains'; isJson=$true })
            paging = @{ pageSize=1; offset=0 }
        }
        exclude = @{ groupsIds=@(); computerIds=@() }
        include = @{ computers=@(@{ id=$Endpoint.ID }) }
    }
    $bodyObj = @{ comment=$comment; timing=@{ expirationSeconds=1; schedulingDateTime=(Get-Date).ToString('o') }; targets=$targets }
    $body    = $bodyObj | ConvertTo-Json -Depth 7

    try {
        $resp  = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType 'application/json' -ErrorAction Stop
        $jobId = $resp.jobId
        Log "Remediation jobId: $jobId"
    } catch {
        LogErr "Remediation submit failed: $($_.Exception.Message)"
        if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
        return
    }

    # Poll remediation status
    $statusUrl = "$BasePath/v1/jobs/$jobId"
    $attempt   = 0
    do {
        Start-Sleep -Seconds ($PollInterval * 2)
        $attempt++
        try {
            $jobStat = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers @{ Authorization = "Bearer $token"; 'x-mgmt-api-token' = $mgmtToken }
            $status  = $jobStat.status
            Log "Raw remediation job status: $(ConvertTo-Json $jobStat -Depth 3)"
            Log "Polling remediation status ($attempt/$MaxPolls): $status"
        } catch {
            if ($_.Exception.Response) {
                $code = $_.Exception.Response.StatusCode.Value__
                if ($code -eq 429) {
                    LogErr "Rate limited polling remediation, backing off..."
                    Start-Sleep -Seconds ($PollInterval * 5)
                    continue
                } elseif ($code -eq 404) {
                    LogErr "Remediation job status not found, retrying..."
                    continue
                }
            }
            LogErr "Polling remediation error: $($_.Exception.Message)"
            if ($_.Exception.Response) { LogErr ReadBody($_.Exception.Response.GetResponseStream()) }
            return
        }
    } until ($status -eq 'DONE' -or $attempt -ge $MaxPolls)

    if ($status -ne 'DONE') {
        LogErr "Remediation job did not complete: $status"
        return
    }
    Log "Remediation job completed: $status"
}

# Main flow
# 1) Initial state
$eps = Get-Endpoints "6) Initial State"
$eps | Format-Table ID,Name,IP,Status,Isolation -AutoSize

# 2) Toggle
Invoke-Remediation $eps[0]

# 3) Wait for endpoint state change
$original = $eps[0].Isolation
Log "Waiting for endpoint to toggle from '$original'..."
$changed = $false
$finalLabel = "Polling Final State"
$attempt  = 0
while (-not $changed -and $attempt -lt $MaxPolls) {
    $attempt++
    Start-Sleep -Seconds $PollInterval
    $eps      = Get-Endpoints $finalLabel
    $current  = $eps[0].Isolation
    Log "Current isolation state: $current"
    if ($current -ne $original) {
        $changed = $true
        Log "State changed from '$original' to '$current'"
        $eps | Format-Table ID,Name,IP,Status,Isolation -AutoSize
    }
}

Log "=== End Script: $scriptRelease ==="
