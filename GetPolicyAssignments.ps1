param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PageSize     = 50,
    [int]   $PollInterval = 2,
    [int]   $MaxPolls     = 30
)

$scriptRelease = "GetPolicyAssignments v1.0 (2025-10-10)"

# Logging functions
function Log($msg)    { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function LogErr($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function LogSuccess($msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

function ReadBody($stream) {
    try { (New-Object System.IO.StreamReader($stream)).ReadToEnd() } catch { "" }
}

function Wait-Job($jobId, $token, $mgmtToken, $gateway) {
    $jobUrl = "$gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/$jobId"
    $attempt = 0
    
    do {
        Start-Sleep -Seconds $PollInterval
        $attempt++
        Log "Polling job $jobId - attempt #$attempt..."
        
        try {
            $resp = Invoke-WebRequest -Uri $jobUrl -Method Get -Headers @{
                Authorization      = "Bearer $token"
                "x-mgmt-api-token" = $mgmtToken
            } -ErrorAction Stop
            
            $json = $resp.Content | ConvertFrom-Json
            $status = $json.status
            Log "Job status: '$status'"
            
            if ($status -eq "DONE") {
                return $json
            }
        } catch {
            LogErr "Job polling failed: $($_.Exception.Message)"
            if ($_.Exception.Response) { 
                LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
            }
            return $null
        }
    } until ($attempt -ge $MaxPolls)
    
    LogErr "Job $jobId did not complete within $MaxPolls attempts."
    return $null
}

function Get-RuleAssignments($ruleId, $token, $mgmtToken, $gateway) {
    Log "Getting assignments for rule ID: $ruleId"
    
    # Get rule assignments using the policy API
    $assignmentsUrl = "$gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/rule-metadata/$ruleId/assignments"
    
    try {
        $resp = Invoke-WebRequest -Uri $assignmentsUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $assignments = ($resp.Content | ConvertFrom-Json)
        return $assignments
    } catch {
        # If direct assignment API fails, try to get assignments through job-based API
        Log "Direct assignment API failed, trying job-based approach..."
        
        try {
            $jobResp = Invoke-WebRequest -Uri $assignmentsUrl -Method Get -Headers @{
                Authorization       = "Bearer $token"
                "x-mgmt-api-token"  = $mgmtToken
                "x-mgmt-run-as-job" = "on"
            } -ErrorAction Stop
            
            $jobJson = $jobResp.Content | ConvertFrom-Json
            $jobId = $jobJson.jobId
            
            if ($jobId) {
                $jobResult = Wait-Job -jobId $jobId -token $token -mgmtToken $mgmtToken -gateway $gateway
                if ($jobResult -and $jobResult.data) {
                    return $jobResult.data
                }
            }
        } catch {
            LogErr "Failed to get assignments for rule $ruleId : $($_.Exception.Message)"
            return @()
        }
    }
    
    return @()
}

# Main script
Log "Script version: $scriptRelease"
Log "=" * 60

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

# 4) Get all rules metadata
Log "Retrieving all policy rules..."
$rulesUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/rule-metadata"

try {
    # First try without job
    $rulesResp = Invoke-WebRequest -Uri $rulesUrl -Method Get -Headers @{
        Authorization      = "Bearer $token"
        "x-mgmt-api-token" = $mgmtToken
    } -ErrorAction Stop
    
    $rulesData = ($rulesResp.Content | ConvertFrom-Json)
} catch {
    # If direct call fails, try with job
    Log "Direct rules API failed, trying job-based approach..."
    
    try {
        $jobResp = Invoke-WebRequest -Uri $rulesUrl -Method Get -Headers @{
            Authorization       = "Bearer $token"
            "x-mgmt-api-token"  = $mgmtToken
            "x-mgmt-run-as-job" = "on"
        } -ErrorAction Stop
        
        $jobJson = $jobResp.Content | ConvertFrom-Json
        $jobId = $jobJson.jobId
        
        if (-not $jobId) {
            LogErr "No job ID returned for rules metadata request"
            exit 1
        }
        
        $jobResult = Wait-Job -jobId $jobId -token $token -mgmtToken $mgmtToken -gateway $gateway
        
        if (-not $jobResult -or -not $jobResult.data) {
            LogErr "Failed to get rules metadata from job"
            exit 1
        }
        
        $rulesData = $jobResult.data
    } catch {
        LogErr "Failed to get rules metadata: $($_.Exception.Message)"
        if ($_.Exception.Response) { 
            LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
        }
        exit 1
    }
}

# Process rules data
$rules = @()
if ($rulesData.rules) {
    $rules = $rulesData.rules
} elseif ($rulesData -is [array]) {
    $rules = $rulesData
} else {
    $rules = @($rulesData)
}

if ($rules.Count -eq 0) {
    LogErr "No rules found in the response"
    exit 1
}

LogSuccess "Found $($rules.Count) policy rules"
Log "=" * 60

# 5) For each rule, get its assignments
$results = @()

foreach ($rule in $rules) {
    $ruleId = $rule.uid
    $ruleName = $rule.name
    $ruleType = $rule.type
    $domain = if ($rule.domain) { $rule.domain.name } else { "Global" }
    
    Log "Processing rule: '$ruleName' (ID: $ruleId)"
    
    # Get assignments for this rule
    $assignments = Get-RuleAssignments -ruleId $ruleId -token $token -mgmtToken $mgmtToken -gateway $gateway
    
    # Format assignments
    $assignmentList = @()
    if ($assignments -and $assignments.Count -gt 0) {
        foreach ($assignment in $assignments) {
            if ($assignment.name) {
                $assignmentType = if ($assignment.type) { $assignment.type } else { "Unknown" }
                $assignmentList += "$($assignment.name) ($assignmentType)"
            }
        }
    }
    
    if ($assignmentList.Count -eq 0) {
        $assignmentList = @("No specific assignments (applies to all)")
    }
    
    # Add to results
    $results += [PSCustomObject]@{
        RuleID      = $ruleId
        RuleName    = $ruleName
        RuleType    = $ruleType
        Domain      = $domain
        Assignments = ($assignmentList -join "; ")
        AssignmentCount = if ($assignmentList[0] -like "No specific*") { 0 } else { $assignmentList.Count }
    }
}

# 6) Display results
Log "=" * 60
LogSuccess "Policy Rules and Their Assignments:"
Log "=" * 60

$results | Sort-Object RuleType, RuleName | Format-Table -AutoSize -Wrap

# Summary
Log "=" * 60
LogSuccess "Summary:"
Log "Total Rules: $($results.Count)"
Log "Rules with specific assignments: $(($results | Where-Object { $_.AssignmentCount -gt 0 }).Count)"
Log "Rules applying to all (no specific assignments): $(($results | Where-Object { $_.AssignmentCount -eq 0 }).Count)"

# Group by rule type
$rulesByType = $results | Group-Object RuleType
foreach ($group in $rulesByType) {
    Log "$($group.Name): $($group.Count) rules"
}

Log "=" * 60
LogSuccess "Script completed successfully - $scriptRelease"
