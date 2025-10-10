Param(
    [string]$CredFile = ".\credenziali.json",
    [string]$CSVFile = ".\PolicyAssignments.csv"
)

function ReadBody($stream) {
    try { 
        (New-Object System.IO.StreamReader($stream)).ReadToEnd() 
    } catch { 
        "" 
    }
}

# 1) Carica credenziali
$creds      = Get-Content $CredFile | ConvertFrom-Json
$ClientID   = $creds.clientId
$AccessKey  = $creds.accessKey  
$Gateway    = $creds.gateway

Write-Host "[INFO] Autenticazione..."

# 2) Auth
$authResp = Invoke-RestMethod -Uri "$Gateway/auth/external" -Method Post `
    -Body (@{clientId=$ClientID;accessKey=$AccessKey}|ConvertTo-Json) `
    -ContentType 'application/json'
$token = $authResp.data.token

# 3) Cloud login
$loginResp = Invoke-WebRequest -Uri "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud" `
    -Method Post -Headers @{Authorization="Bearer $token"} -Body '{}' -ContentType 'application/json'
$mgmtToken = $loginResp.Headers['x-mgmt-api-token']

Write-Host "[OK] Cloud login completato"

# 4) Richiesta job-based alle policy metadata
$policyUrl  = "$Gateway/app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata"
$jobResponse = Invoke-WebRequest -Uri $policyUrl -Method Get -Headers @{
    Authorization        = "Bearer $token"
    "x-mgmt-api-token"   = $mgmtToken
    "x-mgmt-run-as-job"  = "on"
} 
$jobJson = $jobResponse.Content | ConvertFrom-Json
$jobId   = $jobJson.jobId

# Polling job
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
    Write-Host "[INFO] Stato job: $status"
} while ($status -ne "DONE" -and $i -lt $maxPolls)

if ($status -ne "DONE") { 
    Write-Host "[ERROR] Timeout polling job"; 
    exit 1 
}

$policies = $pollJson.data

# Costruisci tabella
$results = @()
foreach ($policy in $policies) {
    if ($policy.assignments -and $policy.assignments.Count -gt 0) {
        foreach ($ass in $policy.assignments) {
            $results += [PSCustomObject]@{
                PolicyName      = $policy.name
                Family          = $policy.family
                AssignmentName  = $ass.name
                AssignmentType  = $ass.type
            }
        }
    }
}

# Calcola larghezze dinamiche delle colonne
$maxPolicyName = ($results | ForEach-Object { $_.PolicyName.Length } | Measure-Object -Maximum).Maximum
$maxFamily = ($results | ForEach-Object { $_.Family.Length } | Measure-Object -Maximum).Maximum
$maxAssignmentName = ($results | ForEach-Object { $_.AssignmentName.Length } | Measure-Object -Maximum).Maximum
$maxAssignmentType = ($results | ForEach-Object { $_.AssignmentType.Length } | Measure-Object -Maximum).Maximum

# Assicurati che le larghezze siano almeno quanto i titoli delle colonne
$col1Width = [Math]::Max($maxPolicyName, "PolicyName".Length) + 2
$col2Width = [Math]::Max($maxFamily, "Family".Length) + 2  
$col3Width = [Math]::Max($maxAssignmentName, "AssignmentName".Length) + 2
$col4Width = [Math]::Max($maxAssignmentType, "AssignmentType".Length) + 2

Write-Host ""
Write-Host ("{0,-$col1Width}{1,-$col2Width}{2,-$col3Width}{3,-$col4Width}" -f "PolicyName", "Family", "AssignmentName", "AssignmentType")
Write-Host ("{0,-$col1Width}{1,-$col2Width}{2,-$col3Width}{3,-$col4Width}" -f ("-"*($col1Width-1)), ("-"*($col2Width-1)), ("-"*($col3Width-1)), ("-"*($col4Width-1)))

foreach ($row in $results) {
    Write-Host ("{0,-$col1Width}{1,-$col2Width}{2,-$col3Width}{3,-$col4Width}" -f $row.PolicyName, $row.Family, $row.AssignmentName, $row.AssignmentType)
}

# Export CSV
$results | Export-Csv -Path $CSVFile -NoTypeInformation -Encoding UTF8
Write-Host "`n[INFO] CSV esportato in $CSVFile"
