param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PageSize     = 50,
    [int]   $PollInterval = 2,
    [int]   $MaxPolls     = 30
)

$scriptRelease = "GetPolicyAssignments v1.1 (2025-10-10)"

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
    
    # Try the assignment endpoint directly first
    $assignmentsUrl = "$gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/rule/$ruleId/assignments"
    
    try {
        $resp = Invoke-WebRequest -Uri $assignmentsUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $assignments = ($resp.Content | ConvertFrom-Json)
        if ($assignments.data) {
            return $assignments.data
        }
        return $assignments
    } catch {
        # If direct call fails, try with job
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
            Log "Assignment API not available for rule $ruleId"
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

# 4) Get all rules metadata - using correct endpoint
Log "Retrieving all policy rules..."
$rulesUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/rules"

# First try direct API call
try {
    $rulesResp = Invoke-WebRequest -Uri $rulesUrl -Method Get -Headers @{
        Authorization      = "Bearer $token"
        "x-mgmt-api-token" = $mgmtToken
    } -ErrorAction Stop
    
    $rulesData = ($rulesResp.Content | ConvertFrom-Json)
    Log "Retrieved rules data directly"
} catch {
    # If direct call fails, try with job-based approach
    Log "Direct rules API failed, trying job-based approach..."
    
    try {
        $jobResp = Invoke-WebRequest -Uri $rulesUrl -Method Post -Headers @{
            Authorization       = "Bearer $token"
            "x-mgmt-api-token"  = $mgmtToken
            "x-mgmt-run-as-job" = "on"
        } -Body '{}' -ContentType 'application/json' -ErrorAction Stop
        
        $jobJson = $jobResp.Content | ConvertFrom-Json
        $jobId = $jobJson.jobId
        
        if (-not $jobId) {
            LogErr "No job ID returned for rules request"
            exit 1
        }
        
        $jobResult = Wait-Job -jobId $jobId -token $token -mgmtToken $mgmtToken -gateway $gateway
        
        if (-not $jobResult -or -not $jobResult.data) {
            LogErr "Failed to get rules from job"
            exit 1
        }
        
        $rulesData = $jobResult.data
        Log "Retrieved rules data via job"
    } catch {
        # Try alternative endpoint for policy rule metadata
        Log "Trying alternative policy endpoint..."
        
        try {
            $altUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy"
            $altResp = Invoke-WebRequest -Uri $altUrl -Method Get -Headers @{
                Authorization      = "Bearer $token"
                "x-mgmt-api-token" = $mgmtToken
            } -ErrorAction Stop
            
            $rulesData = ($altResp.Content | ConvertFrom-Json)
            Log "Retrieved policy data from alternative endpoint"
        } catch {
            LogErr "All policy API endpoints failed: $($_.Exception.Message)"
            if ($_.Exception.Response) { 
                LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
            }
            exit 1
        }
    }
}

# Process rules data - handle different response formats
$rules = @()
if ($rulesData.data -and $rulesData.data.rules) {
    $rules = $rulesData.data.rules
} elseif ($rulesData.rules) {
    $rules = $rulesData.rules
} elseif ($rulesData.data -and $rulesData.data -is [array]) {
    $rules = $rulesData.data
} elseif ($rulesData -is [array]) {
    $rules = $rulesData
} else {
    # Try to find rules in any nested property
    $properties = $rulesData | Get-Member -MemberType NoteProperty
    foreach ($prop in $properties) {
        if ($prop.Name -like "*rule*" -and $rulesData.($prop.Name) -is [array]) {
            $rules = $rulesData.($prop.Name)
            Log "Found rules in property: $($prop.Name)"
            break
        }
    }
}

if ($rules.Count -eq 0) {
    LogErr "No rules found in the response"
    Log "Response structure: $(ConvertTo-Json $rulesData -Depth 2)"
    
    # Try to list available policy components
    try {
        $componentsUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/components"
        $compResp = Invoke-WebRequest -Uri $componentsUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $components = ($compResp.Content | ConvertFrom-Json)
        Log "Available policy components: $(ConvertTo-Json $components -Depth 2)"
    } catch {
        Log "Could not retrieve policy components"
    }
    
    exit 1
}

LogSuccess "Found $($rules.Count) policy rules"
Log "=" * 60

# 5) For each rule, get its assignments
$results = @()

foreach ($rule in $rules) {
    # Handle different rule ID field names
    $ruleId = $null
    $ruleName = "Unknown"
    $ruleType = "Unknown"
    $domain = "Global"
    
    # Try different possible field names for rule ID
    if ($rule.uid) { $ruleId = $rule.uid }
    elseif ($rule.id) { $ruleId = $rule.id }
    elseif ($rule.rule_id) { $ruleId = $rule.rule_id }
    elseif ($rule.ruleId) { $ruleId = $rule.ruleId }
    
    # Try different possible field names for rule name
    if ($rule.name) { $ruleName = $rule.name }
    elseif ($rule.rule_name) { $ruleName = $rule.rule_name }
    elseif ($rule.ruleName) { $ruleName = $rule.ruleName }
    
    # Try different possible field names for rule type
    if ($rule.type) { $ruleType = $rule.type }
    elseif ($rule.rule_type) { $ruleType = $rule.rule_type }
    elseif ($rule.ruleType) { $ruleType = $rule.ruleType }
    elseif ($rule.family) { $ruleType = $rule.family }
    
    # Try different possible field names for domain
    if ($rule.domain -and $rule.domain.name) { $domain = $rule.domain.name }
    elseif ($rule.domain -and $rule.domain -is [string]) { $domain = $rule.domain }
    
    if (-not $ruleId) {
        Log "Skipping rule without valid ID: $(ConvertTo-Json $rule -Depth 1)"
        continue
    }
    
    Log "Processing rule: '$ruleName' (ID: $ruleId, Type: $ruleType)"
    
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

if ($results.Count -gt 0) {
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
} else {
    LogErr "No valid rules were processed"
}

Log "=" * 60
LogSuccess "Script completed - $scriptRelease"