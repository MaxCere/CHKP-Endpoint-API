#requires -Version 5.1
&lt;#
.SYNOPSIS
    GetAuditConfigChanges.ps1 - Check Point Audit/Configuration Changes Extractor

.DESCRIPTION
    Extracts audit and configuration change events from Check Point Infinity Events API.
    Follows patterns from GetInfinityEvents.ps1 with audit-specific base filter.

.PARAMETER CredFile
    Path to credentials JSON (clientId, accessKey, gateway)

.PARAMETER StartTime
    Start time ISO8601 (e.g. '2025-12-01T00:00:00Z')

.PARAMETER EndTime
    End time ISO8601

.PARAMETER Filter
    Additional Lucene filter (combined with base audit filter)

.PARAMETER Limit
    Max total records (default: 1000)

.PARAMETER PageLimit
    Records per page (default: 100)

.PARAMETER ExportCSV
    Export results to CSV

.PARAMETER CSVFile
    Custom CSV output path

.PARAMETER Debug
    Enable debug logging

.EXAMPLE
    .\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json

.EXAMPLE
    .\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json -StartTime '2025-12-01T00:00:00Z' -EndTime '2025-12-04T23:59:59Z' -ExportCSV
#&gt;

param(
    [Parameter(Mandatory=$false)]
    [string]$CredFile = 'credenziali_infinity_events.json',
    
    [string]$StartTime,
    [string]$EndTime,
    
    [string]$Filter,
    
    [int]$Limit = 1000,
    [int]$PageLimit = 100,
    
    [switch]$ExportCSV,
    [string]$CSVFile,
    
    [switch]$Debug,
    [int]$PollInterval = 5,
    [int]$MaxPolls = 60
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $color = switch($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'DEBUG' { 'Cyan' }
        default { 'Green' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Credentials {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Log "File credenziali non trovato: $Path" 'ERROR'
        return $false
    }
    try {
        $creds = Get-Content $Path | ConvertFrom-Json
        if ($creds.clientId -and $creds.accessKey -and $creds.gateway) {
            Write-Log "Credenziali caricate da: $Path"
            return $true
        }
        Write-Log "Credenziali incomplete in $Path" 'ERROR'
        return $false
    }
    catch {
        Write-Log "Errore lettura credenziali: $_" 'ERROR'
        return $false
    }
}

function Invoke-Rest {
    param($Uri, $Method, $Body, $Headers, [switch]$DebugLog)
    
    if ($DebugLog -and $Debug) {
        Write-Log "DEBUG: $Method $Uri" 'DEBUG'
        if ($Body) { Write-Log "DEBUG Body: $Body" 'DEBUG' }
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Uri -Method $Method -Body $Body -Headers $Headers -ContentType 'application/json'
        return $response
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        Write-Log "HTTP $status`: $msg" 'ERROR'
        if ($Debug) { Write-Log "Response: $($_.Exception.Response)" 'DEBUG' }
        throw
    }
}

function Get-AuthToken {
    param($Creds)
    
    $authBody = @{
        clientId = $Creds.clientId
        accessKey = $Creds.accessKey
    } | ConvertTo-Json
    
    Write-Log 'Autenticazione in corso...'
    $tokenResponse = Invoke-Rest -Uri "$($Creds.gateway)/auth/external" -Method 'POST' -Body $authBody -Headers @{} -DebugLog
    
    if ($tokenResponse.success -eq $true) {
        Write-Log '[SUCCESS] Autenticazione completata' 'INFO'
        return $tokenResponse.data.token
    }
    throw 'Autenticazione fallita'
}

function New-LogsQuery {
    param($Token, $Creds, $StartTime, $EndTime, $UserFilter, $Limit, $PageLimit)
    
    # BASE AUDIT FILTER - Targets configuration/audit changes
    $baseFilter = '(product:"Infinity Portal" OR category:"audit" OR eventType:"configuration" OR eventType:"policy" OR eventType:"object")'
    
    if ($UserFilter) {
        $finalFilter = "($baseFilter) AND ($UserFilter)"
        Write-Log "Filtro applicato: $finalFilter"
    } else {
        $finalFilter = $baseFilter
        Write-Log "Base audit filter: $baseFilter"
    }
    
    $timeframe = @{}
    if ($StartTime -or $EndTime) {
        $timeframe.startTime = if ($StartTime) { $StartTime } else { (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        $timeframe.endTime = if ($EndTime) { $EndTime } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        Write-Log "Timeframe: $($timeframe.startTime) to $($timeframe.endTime)"
    }
    
    $queryBody = @{
        limit = $Limit
        pageLimit = $PageLimit
        filter = $finalFilter
        cloudService = 'Infinity Portal'
    }
    if ($timeframe.Count -gt 0) { $queryBody.timeframe = $timeframe }
    
    $queryBody = $queryBody | ConvertTo-Json -Depth 10
    
    Write-Log "Creazione task di ricerca..."
    $queryResponse = Invoke-Rest -Uri "$($Creds.gateway)/app/laas-logs-api/api/logs_query" `
        -Method 'POST' `
        -Body $queryBody `
        -Headers @{ 'Authorization' = "Bearer $Token" }
    
    return $queryResponse.data.taskId
}

function Wait-TaskReady {
    param($Token, $Creds, $TaskId, $MaxPolls, $PollInterval)
    
    Write-Log "Task creato: $TaskId"
    
    for ($i = 1; $i -le $MaxPolls; $i++) {
        Start-Sleep -Seconds $PollInterval
        
        $statusResponse = Invoke-Rest -Uri "$($Creds.gateway)/app/laas-logs-api/api/logs_query/$TaskId" `
            -Method 'GET' `
            -Headers @{ 'Authorization' = "Bearer $Token" }
        
        $state = $statusResponse.data.state
        Write-Log "Poll $i/$MaxPolls - State: $state"
        
        if ($state -eq 'Ready') {
            Write-Log 'Task completato'
            return $statusResponse.data.pageTokens
        }
        
        if ($state -eq 'Failed') {
            throw "Task fallito"
        }
    }
    
    throw "Timeout dopo $MaxPolls polls"
}

function Get-PageRecords {
    param($Token, $Creds, $TaskId, $PageToken)
    
    $pageBody = @{ taskId = $TaskId; pageToken = $PageToken } | ConvertTo-Json
    
    try {
        $pageResponse = Invoke-Rest -Uri "$($Creds.gateway)/app/laas-logs-api/api/logs_query/retrieve" `
            -Method 'POST' `
            -Body $pageBody `
            -Headers @{ 'Authorization' = "Bearer $Token" }
        
        return $pageResponse.data.records
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 400) {
            Write-Log "Fine dati pagina: $PageToken" 'WARN'
            return @()
        }
        throw
    }
}

function ConvertTo-AuditRecord {
    param($Record)
    
    $auditRecord = [PSCustomObject]@{
        Timestamp = $Record.'@timestamp' ?? $Record.timestamp ?? ''
        User = $Record.user ?? $Record.username ?? $Record.actor ?? ''
        ActionType = $Record.eventType ?? $Record.action ?? $Record.operation ?? ''
        ObjectType = $Record.objectType ?? $Record.category ?? $Record.resourceType ?? ''
        ObjectName = $Record.objectName ?? $Record.resource ?? $Record.target ?? ''
        Source = $Record.product ?? $Record.source ?? $Record.service ?? ''
        Result = $Record.result ?? $Record.status ?? ''
        Severity = $Record.severity ?? ''
        EventId = $Record.id ?? $Record.eventId ?? ''
        RawDetails = ($Record | ConvertTo-Json -Compress)
    }
    
    return $auditRecord
}

# MAIN EXECUTION
try {
    if ($Debug) { Write-Log 'Debug mode abilitato' 'DEBUG' }
    
    # Load credentials
    if (-not (Test-Credentials $CredFile)) { exit 1 }
    $creds = Get-Content $CredFile | ConvertFrom-Json
    
    # Authenticate
    $token = Get-AuthToken $creds
    
    # Create query
    $taskId = New-LogsQuery -Token $token -Creds $creds -StartTime $StartTime -EndTime $EndTime -UserFilter $Filter -Limit $Limit -PageLimit $PageLimit
    
    # Wait for completion
    $pageTokens = Wait-TaskReady -Token $token -Creds $creds -TaskId $taskId -MaxPolls $MaxPolls -PollInterval $PollInterval
    
    # Retrieve all pages
    $allRecords = @()
    foreach ($pageToken in $pageTokens) {
        Write-Log "Recupero pagina: $pageToken"
        $pageRecords = Get-PageRecords -Token $token -Creds $creds -TaskId $taskId -PageToken $pageToken
        $allRecords += $pageRecords
        Write-Log "Recuperati $($pageRecords.Count) record da questa pagina"
    }
    
    Write-Log "[SUCCESS] Totale record recuperati: $($allRecords.Count)" 'INFO'
    
    # Convert to audit records
    $auditRecords = $allRecords | ForEach-Object { ConvertTo-AuditRecord $_ }
    
    # Summary statistics
    Write-Log "\n=== STATISTICHE AUDIT ===" 'INFO'
    Write-Log "Totali eventi configurazione: $($auditRecords.Count)" 'INFO'
    
    $userStats = $auditRecords | Group-Object User | Sort-Object Count -Descending | Select-Object -First 10
    Write-Log "Top 10 utenti (eventi):"
    $userStats | ForEach-Object { Write-Log "  $($_.Name): $($_.Count)" }
    
    $actionStats = $auditRecords | Group-Object ActionType | Sort-Object Count -Descending | Select-Object -First 10
    Write-Log "Top 10 azioni:"
    $actionStats | ForEach-Object { Write-Log "  $($_.Name): $($_.Count)" }
    
    # Export CSV
    if ($ExportCSV) {
        $csvPath = if ($CSVFile) { $CSVFile } else { "AuditChanges_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" }
        
        $auditRecords | Select-Object Timestamp, User, ActionType, ObjectType, ObjectName, Source, Result, Severity, EventId | 
            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        
        Write-Log "Esportato CSV: $csvPath" 'INFO'
    }
    
    Write-Log '[SUCCESS] Script completato' 'INFO'
    
} catch {
    Write-Log "ERRORE: $_" 'ERROR'
    exit 1
}