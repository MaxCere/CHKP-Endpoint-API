Param(
    [string]$CredFile = ".\credenziali.json",
    [string]$CSVFile = ".\VirtualGroupUsage.csv"
)

function ReadBody($stream) {
    try { 
        (New-Object System.IO.StreamReader($stream)).ReadToEnd() 
    } catch { 
        "" 
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp][$Level] $Message"
}

function Exit-WithError {
    param(
        [string]$ErrorMessage
    )
    Write-Log -Message $ErrorMessage -Level "ERROR"
    exit 1
}

# Verifica esistenza file credenziali
if (-not (Test-Path $CredFile)) {
    Exit-WithError "Credentials file not found: $CredFile"
}

try {
    # 1) Load credentials
    Write-Log "Loading credentials from $CredFile"
    $creds = Get-Content $CredFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    
    if (-not $creds.clientId -or -not $creds.accessKey -or -not $creds.gateway) {
        Exit-WithError "Invalid credentials format. Required: clientId, accessKey, gateway"
    }
    
    $ClientID = $creds.clientId
    $AccessKey = $creds.accessKey  
    $Gateway = $creds.gateway
    
    Write-Log "Credentials loaded successfully"
    
} catch {
    Exit-WithError "Failed to load credentials: $($_.Exception.Message)"
}

# 2) Authentication
Write-Log "Starting authentication process..."

try {
    $authBody = @{
        clientId = $ClientID
        accessKey = $AccessKey
    } | ConvertTo-Json
    
    $authResp = Invoke-RestMethod -Uri "$Gateway/auth/external" -Method Post `
        -Body $authBody -ContentType 'application/json' -ErrorAction Stop
    
    # Verifica risposta autenticazione
    if (-not $authResp) {
        Exit-WithError "Empty authentication response"
    }
    
    if ($authResp.success -eq $false) {
        Exit-WithError "Authentication failed: $($authResp.message)"
    }
    
    if (-not $authResp.data -or -not $authResp.data.token) {
        Exit-WithError "No token received in authentication response"
    }
    
    $token = $authResp.data.token
    Write-Log "Authentication successful"
    
} catch {
    if ($_.Exception.Message -like "*401*" -or $_.Exception.Message -like "*Unauthorized*") {
        Exit-WithError "Authentication failed: Invalid credentials (401 Unauthorized)"
    } elseif ($_.Exception.Message -like "*403*" -or $_.Exception.Message -like "*Forbidden*") {
        Exit-WithError "Authentication failed: Access forbidden (403 Forbidden)"
    } else {
        Exit-WithError "Authentication request failed: $($_.Exception.Message)"
    }
}

# Validazione token
if ([string]::IsNullOrEmpty($token)) {
    Exit-WithError "Token is null or empty after successful authentication"
}

# 3) Cloud login
Write-Log "Performing cloud login..."

try {
    $loginResp = Invoke-WebRequest -Uri "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud" `
        -Method Post -Headers @{Authorization="Bearer $token"} `
        -Body '{}' -ContentType 'application/json' -ErrorAction Stop
    
    # Accetta tutti i codici di successo 2xx (200-299)
    if ($loginResp.StatusCode -lt 200 -or $loginResp.StatusCode -ge 300) {
        Exit-WithError "Cloud login failed with status code: $($loginResp.StatusCode)"
    }
    
    $mgmtToken = $loginResp.Headers['x-mgmt-api-token']
    
    if ([string]::IsNullOrEmpty($mgmtToken)) {
        Exit-WithError "No management token received from cloud login"
    }
    
    Write-Log "Cloud login completed successfully (Status: $($loginResp.StatusCode))"
    
} catch {
    Exit-WithError "Cloud login failed: $($_.Exception.Message)"
}

# 4) Query policy metadata as job
Write-Log "Starting policy metadata query job..."

try {
    $policyUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata"
    $jobResponse = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
        Authorization        = "Bearer $token"
        "x-mgmt-api-token"   = $mgmtToken
        "x-mgmt-run-as-job"  = "on"
    } -ErrorAction Stop
    
    # Accetta tutti i codici di successo 2xx
    if ($jobResponse.StatusCode -lt 200 -or $jobResponse.StatusCode -ge 300) {
        Exit-WithError "Job creation failed with status code: $($jobResponse.StatusCode)"
    }
    
    $jobJson = $jobResponse.Content | ConvertFrom-Json -ErrorAction Stop
    
    if (-not $jobJson.jobId) {
        Exit-WithError "No job ID received from policy metadata request"
    }
    
    $jobId = $jobJson.jobId
    Write-Log "Job created successfully with ID: $jobId"
    
} catch {
    Exit-WithError "Failed to create policy metadata job: $($_.Exception.Message)"
}

# 5) Poll job status
Write-Log "Polling job status..."

$jobUrl = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/$jobId"
$i = 0
$maxPolls = 30
$status = ""
$pollJson = $null

do {
    Start-Sleep -Seconds 2
    $i++
    
    try {
        $pollResp = Invoke-WebRequest -Uri $jobUrl -Method Get -Headers @{
            Authorization      = "Bearer $token"
            "x-mgmt-api-token" = $mgmtToken
        } -ErrorAction Stop
        
        $pollJson = $pollResp.Content | ConvertFrom-Json -ErrorAction Stop
        $status = $pollJson.status
        
        Write-Log "Job status: $status (Poll $i/$maxPolls)"
        
        if ($status -eq "FAILED" -or $status -eq "ERROR") {
            Exit-WithError "Job failed with status: $status"
        }
        
    } catch {
        Exit-WithError "Job polling failed: $($_.Exception.Message)"
    }
    
} while ($status -ne "DONE" -and $i -lt $maxPolls)

if ($status -ne "DONE") { 
    Exit-WithError "Job polling timeout after $maxPolls attempts"
}

if (-not $pollJson.data) {
    Exit-WithError "No data received from completed job"
}

$policies = $pollJson.data
Write-Log "Job completed successfully. Retrieved $($policies.Count) policies"

# 6) Process Virtual Groups
Write-Log "Processing Virtual Groups from policies..."

$virtualGroupUsage = @{}
$totalPoliciesProcessed = 0

foreach ($policy in $policies) {
    $totalPoliciesProcessed++
    
    if ($policy.assignments -and $policy.assignments.Count -gt 0) {
        foreach ($ass in $policy.assignments) {
            if ($ass.type -eq "VIRTUAL_GROUP") {
                $vgName = $ass.name
                
                if (-not $virtualGroupUsage.ContainsKey($vgName)) {
                    $virtualGroupUsage[$vgName] = @{
                        VirtualGroupName = $vgName
                        VirtualGroupID = $ass.id
                        PolicyCount = 0
                        Policies = @()
                        PolicyFamilies = @()
                    }
                }
                
                $virtualGroupUsage[$vgName].PolicyCount++
                $virtualGroupUsage[$vgName].Policies += $policy.name
                $virtualGroupUsage[$vgName].PolicyFamilies += $policy.family
            }
        }
    }
}

Write-Log "Processed $totalPoliciesProcessed policies"
Write-Log "Found $($virtualGroupUsage.Keys.Count) Virtual Groups in use"

# 7) Generate results
if ($virtualGroupUsage.Keys.Count -eq 0) {
    Write-Log "No Virtual Groups found in any policies" -Level "WARN"
    Write-Host "`nNo Virtual Groups are currently used in any policies."
} else {
    # Table output
    $results = @()
    foreach ($vgName in $virtualGroupUsage.Keys) {
        $vg = $virtualGroupUsage[$vgName]
        for ($i = 0; $i -lt $vg.Policies.Count; $i++) {
            $results += [PSCustomObject]@{
                VirtualGroupName = $vg.VirtualGroupName
                VirtualGroupID   = $vg.VirtualGroupID
                PolicyName       = $vg.Policies[$i]
                PolicyFamily     = $vg.PolicyFamilies[$i]
                TotalPoliciesInVG = $vg.PolicyCount
            }
        }
    }
    
    Write-Host "`nVirtual Groups used in Policies:"
    $results | Sort-Object VirtualGroupName, PolicyFamily, PolicyName | 
        Format-Table -Property VirtualGroupName, PolicyName, PolicyFamily, TotalPoliciesInVG -AutoSize
    
    # Summary statistics
    Write-Host "`n=== VIRTUAL GROUPS STATISTICS ==="
    Write-Host "Total Virtual Groups in use: $($virtualGroupUsage.Keys.Count)"
    Write-Host "`nVirtual Groups by policy count:"
    $virtualGroupUsage.Values | Sort-Object PolicyCount -Descending | ForEach-Object {
        Write-Host "  - $($_.VirtualGroupName): $($_.PolicyCount) policies"
    }
    
    # Policy families using Virtual Groups
    $familiesUsingVG = $results | Group-Object PolicyFamily | Sort-Object Count -Descending
    Write-Host "`nPolicy families using Virtual Groups:"
    foreach ($family in $familiesUsingVG) {
        Write-Host "  - $($family.Name): $($family.Count) assignments"
    }
    
    # 8) Export CSV
    try {
        $results | Export-Csv -Path $CSVFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "CSV exported successfully to $CSVFile"
        
        # Export Virtual Group summary
        $summaryResults = @()
        foreach ($vgName in $virtualGroupUsage.Keys) {
            $vg = $virtualGroupUsage[$vgName]
            $summaryResults += [PSCustomObject]@{
                VirtualGroupName = $vg.VirtualGroupName
                VirtualGroupID   = $vg.VirtualGroupID
                PolicyCount      = $vg.PolicyCount
                PolicyList       = ($vg.Policies -join "; ")
                FamilyList       = (($vg.PolicyFamilies | Sort-Object -Unique) -join "; ")
            }
        }
        
        $summaryFile = $CSVFile -replace "\.csv$", "_Summary.csv"
        $summaryResults | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Virtual Groups summary exported to $summaryFile"
        
    } catch {
        Write-Log "Failed to export CSV files: $($_.Exception.Message)" -Level "WARN"
    }
}

Write-Log "Script execution completed successfully"