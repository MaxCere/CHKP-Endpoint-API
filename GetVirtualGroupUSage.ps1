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

# 1) Load credentials
$creds      = Get-Content $CredFile | ConvertFrom-Json
$ClientID   = $creds.clientId
$AccessKey  = $creds.accessKey  
$Gateway    = $creds.gateway

Write-Host "[INFO] Authentication..."

# 2) Get token
$authResp = Invoke-RestMethod -Uri "$Gateway/auth/external" -Method Post `
    -Body (@{clientId=$ClientID;accessKey=$AccessKey}|ConvertTo-Json) `
    -ContentType 'application/json'
$token = $authResp.data.token

# 3) Cloud login
$loginResp = Invoke-WebRequest -Uri "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud" `
    -Method Post -Headers @{Authorization="Bearer $token"} -Body '{}' -ContentType 'application/json'
$mgmtToken = $loginResp.Headers['x-mgmt-api-token']

Write-Host "[OK] Cloud login completed"

# 4) Query policy metadata as job
$policyUrl  = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata"
$jobResponse = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
    Authorization        = "Bearer $token"
    "x-mgmt-api-token"   = $mgmtToken
    "x-mgmt-run-as-job"  = "on"
} 
$jobJson = $jobResponse.Content | ConvertFrom-Json
$jobId   = $jobJson.jobId

# Poll job
$jobUrl    = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/$jobId"
$i         = 0
$maxPolls  = 30
$status    = ""

do {
    Start-Sleep -Seconds 2
    $i++
    $pollResp = Invoke-WebRequest -Uri $jobUrl -Method Get -Headers @{
        Authorization      = "Bearer $token"
        "x-mgmt-api-token" = $mgmtToken
    }
    $pollJson = $pollResp.Content | ConvertFrom-Json
    $status   = $pollJson.status
    Write-Host "[INFO] Job status: $status"
} while ($status -ne "DONE" -and $i -lt $maxPolls)

if ($status -ne "DONE") { 
    Write-Host "[ERROR] Job polling timeout"; 
    exit 1 
}

$policies = $pollJson.data

# Extract Virtual Groups from policies
$virtualGroupUsage = @{}

foreach ($policy in $policies) {
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

# Export CSV
$results | Export-Csv -Path $CSVFile -NoTypeInformation -Encoding UTF8
Write-Host "`n[INFO] CSV exported to $CSVFile"

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
$summaryResults | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
Write-Host "[INFO] Virtual Groups summary exported to $summaryFile"
