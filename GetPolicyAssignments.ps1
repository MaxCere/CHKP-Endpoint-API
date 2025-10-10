param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PollInterval = 2,
    [int]   $MaxPolls     = 30,
    [switch]$ExportCSV
)

$scriptRelease = "GetPolicyAssignments v3.0 (2025-10-10) - Working Final Version"

# Logging functions
function Log($msg)    { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function LogErr($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function LogSuccess($msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

function ReadBody($stream) {
    try { (New-Object System.IO.StreamReader($stream)).ReadToEnd() } catch { "" }
}

# Main script
Log "Script version: $scriptRelease"
Log "=" * 70

# 1) Load credentials
if (-not (Test-Path $CredFile)) { 
    LogErr "Credentials file missing: $CredFile"
    exit 1 
}

try {
    $creds = Get-Content $CredFile | ConvertFrom-Json
    $ClientID = $creds.clientId
    $AccessKey = $creds.accessKey
    $Gateway = $creds.gateway
    Log "Using Gateway: $Gateway"
} catch {
    LogErr "Failed to load credentials: $($_.Exception.Message)"
    exit 1
}

# 2) Authentication
Log "Authenticating with Infinity Portal..."
try {
    $authResp = Invoke-RestMethod -Uri "$Gateway/auth/external" -Method Post `
        -Body (@{clientId=$ClientID;accessKey=$AccessKey}|ConvertTo-Json) `
        -ContentType 'application/json' -ErrorAction Stop
    $token = $authResp.data.token
    Log "Authentication successful"
} catch {
    LogErr "Authentication failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { 
        LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
    }
    exit 1
}

# 3) Cloud login
Log "Performing cloud login..."
try {
    $loginResp = Invoke-WebRequest -Uri "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud" `
        -Method Post -Headers @{Authorization="Bearer $token"} `
        -Body '{}' -ContentType 'application/json' -ErrorAction Stop
    $mgmtToken = $loginResp.Headers['x-mgmt-api-token']
    Log "Cloud login successful"
} catch {
    LogErr "Cloud login failed: $($_.Exception.Message)"
    if ($_.Exception.Response) { 
        LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
    }
    exit 1
}

# 4) Request policy metadata using job-based approach
Log "Retrieving all policy rules metadata..."
$policyUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata"

try {
    $jobResponse = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
        Authorization = "Bearer $token"
        "x-mgmt-api-token" = $mgmtToken
        "x-mgmt-run-as-job" = "on"
    } -ErrorAction Stop
    
    $jobJson = $jobResponse.Content | ConvertFrom-Json
    
    if (-not $jobJson.jobId) {
        LogErr "jobId not found in response"
        exit 1
    }
    
    $jobId = $jobJson.jobId
    Log "Job ID: $jobId"
} catch {
    LogErr "Failed to request policy metadata: $($_.Exception.Message)"
    if ($_.Exception.Response) { 
        LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
    }
    exit 1
}

# 5) Poll job until completion
Log "Polling job for completion..."
$jobUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/$jobId"
$attempt = 0

do {
    Start-Sleep -Seconds $PollInterval
    $attempt++
    Log "Polling job - attempt #$attempt..."
    
    try {
        $pollResp = Invoke-WebRequest -Uri $jobUrl -Method Get -Headers @{
            Authorization = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $pollJson = $pollResp.Content | ConvertFrom-Json
        $status = $pollJson.status
        Log "Job status: '$status'"
        
        if ($status -eq "DONE") {
            break
        }
    } catch {
        LogErr "Job polling failed: $($_.Exception.Message)"
        exit 1
    }
} until ($attempt -ge $MaxPolls)

if ($status -ne "DONE") {
    LogErr "Job did not complete within $MaxPolls attempts"
    exit 1
}

# 6) Process results
$policies = $pollJson.data

if (-not $policies -or $policies.Count -eq 0) {
    LogErr "No policies found in job response"
    exit 1
}

LogSuccess "Found $($policies.Count) policy rules"

# 7) Create results array
$results = @()

foreach ($policy in $policies) {
    $ruleName = if ($policy.name) { $policy.name } else { "Unknown" }
    $ruleId = if ($policy.id) { $policy.id } else { "Unknown" }
    $ruleFamily = if ($policy.family) { $policy.family } else { "Unknown" }
    $connectionState = if ($policy.connectionState) { $policy.connectionState } else { "N/A" }
    $isDefault = if ($policy.isDefaultRule) { $policy.isDefaultRule } else { $false }
    $assignments = $policy.assignments
    
    if ($assignments -and $assignments.Count -gt 0) {
        foreach ($assignment in $assignments) {
            $results += [PSCustomObject]@{
                PolicyName = $ruleName
                PolicyID = $ruleId
                Family = $ruleFamily
                ConnectionState = $connectionState
                IsDefaultRule = $isDefault
                AssignmentName = $assignment.name
                AssignmentType = $assignment.type
                AssignmentID = if ($assignment.id) { $assignment.id } else { "" }
            }
        }
    } else {
        $results += [PSCustomObject]@{
            PolicyName = $ruleName
            PolicyID = $ruleId
            Family = $ruleFamily
            ConnectionState = $connectionState
            IsDefaultRule = $isDefault
            AssignmentName = "No specific assignments"
            AssignmentType = "GLOBAL"
            AssignmentID = ""
        }
    }
}

# 8) Display results
Log ""
Log "=" * 70
LogSuccess "Policy Rules and Their Assignments:"
Log "=" * 70

$results | Sort-Object Family, PolicyName, AssignmentType | Format-Table -AutoSize -Wrap

# 9) Export to CSV if requested
if ($ExportCSV) {
    $csvFile = "PolicyAssignments_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    try {
        $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        LogSuccess "Results exported to: $csvFile"
    } catch {
        LogErr "Failed to export CSV: $($_.Exception.Message)"
    }
}

# 10) Summary statistics
Log ""
Log "=" * 70
LogSuccess "Summary Statistics:"
Log "Total Policy Rules: $($policies.Count)"
Log "Total Assignments: $($results.Count)"

$withSpecificAssignments = ($results | Where-Object { $_.AssignmentType -ne "GLOBAL" }).Count
$globalAssignments = ($results | Where-Object { $_.AssignmentType -eq "GLOBAL" }).Count

Log "Rules with specific assignments: $withSpecificAssignments"
Log "Rules with global assignments: $globalAssignments"

# Group by family
$familyStats = $policies | Group-Object family
Log ""
Log "Rules by Family:"
foreach ($family in $familyStats) {
    Log "  - $($family.Name): $($family.Count) rules"
}

# Group by assignment type
$assignmentStats = $results | Where-Object { $_.AssignmentType -ne "GLOBAL" } | Group-Object AssignmentType
if ($assignmentStats.Count -gt 0) {
    Log ""
    Log "Assignment Types:"
    foreach ($type in $assignmentStats) {
        Log "  - $($type.Name): $($type.Count) assignments"
    }
}

# Show top assigned entities
$topAssignments = $results | Where-Object { $_.AssignmentType -ne "GLOBAL" } | 
                  Group-Object AssignmentName | 
                  Sort-Object Count -Descending | 
                  Select-Object -First 5

if ($topAssignments.Count -gt 0) {
    Log ""
    Log "Top 5 Most Assigned Entities:"
    foreach ($assignment in $topAssignments) {
        Log "  - $($assignment.Name): $($assignment.Count) policy rules"
    }
}

Log ""
Log "=" * 70
LogSuccess "Script completed successfully - $scriptRelease"
LogSuccess "Usage: .\GetPolicyAssignments.ps1 [-CredFile credenziali.json] [-ExportCSV]"