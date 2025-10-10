param(
    [string]$CredFile    = ".\credenziali.json",
    [int]   $PageSize     = 50,
    [int]   $PollInterval = 2,
    [int]   $MaxPolls     = 30
)

$scriptRelease = "GetPolicyAssignments v1.2 (2025-10-10)"

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

function Get-PolicyDetails($policyId, $token, $mgmtToken, $gateway) {
    Log "Getting details for policy ID: $policyId"
    
    # Get policy details with assignments
    $policyUrl = "$gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/desktop-policy/$policyId"
    
    try {
        $resp = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $policyDetails = ($resp.Content | ConvertFrom-Json)
        return $policyDetails
    } catch {
        # If direct call fails, try with job
        Log "Direct policy details API failed, trying job-based approach..."
        
        try {
            $jobResp = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
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
            LogErr "Failed to get policy details for $policyId : $($_.Exception.Message)"
            return $null
        }
    }
    
    return $null
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

# 4) Get all desktop policies - using correct endpoint
Log "Retrieving all desktop policies..."
$policiesUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/desktop-policy"

# First try direct API call
try {
    $policiesResp = Invoke-WebRequest -Uri $policiesUrl -Method Get -Headers @{
        Authorization      = "Bearer $token"
        "x-mgmt-api-token" = $mgmtToken
    } -ErrorAction Stop
    
    $policiesData = ($policiesResp.Content | ConvertFrom-Json)
    Log "Retrieved policies data directly"
} catch {
    # If direct call fails, try with job-based approach
    Log "Direct policies API failed, trying job-based approach..."
    
    try {
        $jobResp = Invoke-WebRequest -Uri $policiesUrl -Method Get -Headers @{
            Authorization       = "Bearer $token"
            "x-mgmt-api-token"  = $mgmtToken
            "x-mgmt-run-as-job" = "on"
        } -ErrorAction Stop
        
        $jobJson = $jobResp.Content | ConvertFrom-Json
        $jobId = $jobJson.jobId
        
        if (-not $jobId) {
            LogErr "No job ID returned for policies request"
            exit 1
        }
        
        $jobResult = Wait-Job -jobId $jobId -token $token -mgmtToken $mgmtToken -gateway $gateway
        
        if (-not $jobResult -or -not $jobResult.data) {
            LogErr "Failed to get policies from job"
            exit 1
        }
        
        $policiesData = $jobResult.data
        Log "Retrieved policies data via job"
    } catch {
        LogErr "All desktop policy API endpoints failed: $($_.Exception.Message)"
        if ($_.Exception.Response) { 
            LogErr (ReadBody($_.Exception.Response.GetResponseStream())) 
        }
        Log "Response content: $($_.Exception.Response)"
        exit 1
    }
}

# Process policies data - handle different response formats
$policies = @()
if ($policiesData.data -and $policiesData.data.policies) {
    $policies = $policiesData.data.policies
} elseif ($policiesData.policies) {
    $policies = $policiesData.policies
} elseif ($policiesData.data -and $policiesData.data -is [array]) {
    $policies = $policiesData.data
} elseif ($policiesData -is [array]) {
    $policies = $policiesData
} else {
    # Try to find policies in any nested property
    $properties = $policiesData | Get-Member -MemberType NoteProperty
    foreach ($prop in $properties) {
        if ($prop.Name -like "*polic*" -and $policiesData.($prop.Name) -is [array]) {
            $policies = $policiesData.($prop.Name)
            Log "Found policies in property: $($prop.Name)"
            break
        }
    }
}

if ($policies.Count -eq 0) {
    LogErr "No policies found in the response"
    Log "Response structure: $(ConvertTo-Json $policiesData -Depth 2)"
    exit 1
}

LogSuccess "Found $($policies.Count) desktop policies"
Log "=" * 60

# 5) For each policy, get its details and assignments
$results = @()

foreach ($policy in $policies) {
    # Handle different policy ID field names
    $policyId = $null
    $policyName = "Unknown"
    $policyType = "Desktop Policy"
    $domain = "Global"
    
    # Try different possible field names for policy ID
    if ($policy.uid) { $policyId = $policy.uid }
    elseif ($policy.id) { $policyId = $policy.id }
    elseif ($policy.policy_id) { $policyId = $policy.policy_id }
    elseif ($policy.policyId) { $policyId = $policy.policyId }
    
    # Try different possible field names for policy name
    if ($policy.name) { $policyName = $policy.name }
    elseif ($policy.policy_name) { $policyName = $policy.policy_name }
    elseif ($policy.policyName) { $policyName = $policy.policyName }
    
    # Try different possible field names for domain
    if ($policy.domain -and $policy.domain.name) { $domain = $policy.domain.name }
    elseif ($policy.domain -and $policy.domain -is [string]) { $domain = $policy.domain }
    
    if (-not $policyId) {
        Log "Skipping policy without valid ID: $(ConvertTo-Json $policy -Depth 1)"
        continue
    }
    
    Log "Processing policy: '$policyName' (ID: $policyId)"
    
    # Get detailed policy information including assignments
    $policyDetails = Get-PolicyDetails -policyId $policyId -token $token -mgmtToken $mgmtToken -gateway $gateway
    
    # Format assignments
    $assignmentList = @()
    if ($policyDetails) {
        # Try different possible field names for assignments
        $assignments = $null
        if ($policyDetails.assignments) { 
            $assignments = $policyDetails.assignments 
        } elseif ($policyDetails.data -and $policyDetails.data.assignments) { 
            $assignments = $policyDetails.data.assignments 
        } elseif ($policyDetails.targets) { 
            $assignments = $policyDetails.targets 
        } elseif ($policyDetails.appliedTo) { 
            $assignments = $policyDetails.appliedTo 
        }
        
        if ($assignments -and $assignments.Count -gt 0) {
            foreach ($assignment in $assignments) {
                if ($assignment.name) {
                    $assignmentType = if ($assignment.type) { $assignment.type } else { "Unknown" }
                    $assignmentList += "$($assignment.name) ($assignmentType)"
                } elseif ($assignment.target -and $assignment.target.name) {
                    $assignmentType = if ($assignment.target.type) { $assignment.target.type } else { "Unknown" }
                    $assignmentList += "$($assignment.target.name) ($assignmentType)"
                }
            }
        }
    }
    
    if ($assignmentList.Count -eq 0) {
        $assignmentList = @("No specific assignments (applies to all)")
    }
    
    # Add to results
    $results += [PSCustomObject]@{
        PolicyID    = $policyId
        PolicyName  = $policyName
        PolicyType  = $policyType
        Domain      = $domain
        Assignments = ($assignmentList -join "; ")
        AssignmentCount = if ($assignmentList[0] -like "No specific*") { 0 } else { $assignmentList.Count }
    }
}

# 6) Display results
Log "=" * 60
LogSuccess "Desktop Policies and Their Assignments:"
Log "=" * 60

if ($results.Count -gt 0) {
    $results | Sort-Object PolicyName | Format-Table -AutoSize -Wrap

    # Summary
    Log "=" * 60
    LogSuccess "Summary:"
    Log "Total Policies: $($results.Count)"
    Log "Policies with specific assignments: $(($results | Where-Object { $_.AssignmentCount -gt 0 }).Count)"
    Log "Policies applying to all (no specific assignments): $(($results | Where-Object { $_.AssignmentCount -eq 0 }).Count)"
    
    # Show assignment distribution
    $maxAssignments = ($results | Measure-Object AssignmentCount -Maximum).Maximum
    if ($maxAssignments -gt 0) {
        Log ""
        Log "Assignment distribution:"
        for ($i = 1; $i -le $maxAssignments; $i++) {
            $count = ($results | Where-Object { $_.AssignmentCount -eq $i }).Count
            if ($count -gt 0) {
                Log "Policies with $i assignment(s): $count"
            }
        }
    }
} else {
    LogErr "No valid policies were processed"
}

Log "=" * 60
LogSuccess "Script completed - $scriptRelease"