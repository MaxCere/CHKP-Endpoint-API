<#
.SYNOPSIS
    PowerShell script per il recupero di event logs da Check Point Infinity Events API

.DESCRIPTION
    Questo script autentica con Check Point Infinity Portal e recupera gli event logs
    da tutti i prodotti Check Point supportati. Ottimizzato basato sui test di debug
    che hanno identificato il formato di query corretto.

.PARAMETER CredFile
    Percorso al file JSON delle credenziali (default: credenziali_infinity_events.json)

.PARAMETER Filter
    Filtro per la ricerca dei log (sintassi Lucene)
    Esempio: 'src:"1.1.1.1" AND severity:"Critical"'

.PARAMETER CloudService
    Prodotto Check Point specifico per filtrare i log
    Valori possibili: "Harmony Connect", "Harmony Endpoint", "Harmony Mobile", 
    "Harmony Email & Collaboration", "Harmony Browse", "Quantum Security Management",
    "Quantum Spark Management", "CloudGuard WA", "Quantum Self-Hosted Management"

.PARAMETER StartTime
    Data/ora di inizio ricerca in formato ISO-8601 (UTC)
    Esempio: "2025-10-15T00:00:00Z"
    NOTA: Se non specificato, usa default API (ultima ora)

.PARAMETER EndTime  
    Data/ora di fine ricerca in formato ISO-8601 (UTC)
    Esempio: "2025-10-17T23:59:59Z"
    NOTA: Se non specificato, usa default API (ora corrente)

.PARAMETER Limit
    Numero massimo di record da recuperare (default: 1000)

.PARAMETER PageLimit
    Numero massimo di record per pagina (default: 100)

.PARAMETER ExportCSV
    Esporta i risultati in un file CSV

.PARAMETER PollInterval
    Intervallo in secondi tra i controlli dello stato del task (default: 5)

.PARAMETER MaxPolls
    Numero massimo di tentativi di polling (default: 60)

.EXAMPLE
    .\GetInfinityEvents.ps1
    
.EXAMPLE  
    .\GetInfinityEvents.ps1 -CloudService "Harmony Endpoint" -Filter 'severity:"High"'

.EXAMPLE
    .\GetInfinityEvents.ps1 -StartTime "2025-10-15T00:00:00Z" -EndTime "2025-10-17T23:59:59Z" -ExportCSV

.EXAMPLE
    .\GetInfinityEvents.ps1 -Limit 500 -Filter 'NOT severity:"Low"' -ExportCSV

.NOTES
    Versione: 2.1
    Autore: MaxCere
    Data: 2025-10-17
    
    Changelog v2.1:
    - Migliorata gestione errori paginazione
    - Aggiunto controllo limiti API durante il recupero
    - Gestione robusta di pageToken non validi
    - Continuazione recupero anche con errori parziali
    
    Requisiti:
    - PowerShell 5.1 o superiore
    - Account con permessi su Check Point Infinity Portal
    - API Key creata in Infinity Portal con servizio "Logs as a Service"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CredFile = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Filter = "",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "Harmony Connect",
        "Harmony Endpoint", 
        "Harmony Mobile",
        "Harmony Email & Collaboration",
        "Harmony Browse",
        "Quantum Security Management",
        "Quantum Spark Management", 
        "CloudGuard WA",
        "Quantum Self-Hosted Management"
    )]
    [string]$CloudService = "",
    
    [Parameter(Mandatory = $false)]
    [string]$StartTime = "",
    
    [Parameter(Mandatory = $false)]
    [string]$EndTime = "",
    
    [Parameter(Mandatory = $false)]
    [int]$Limit = 1000,
    
    [Parameter(Mandatory = $false)]
    [int]$PageLimit = 100,
    
    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV,
    
    [Parameter(Mandatory = $false)]
    [int]$PollInterval = 5,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxPolls = 60
)

# Funzioni di utilità
function Log($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Green 
}

function LogError($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] $msg" -ForegroundColor Red 
}

function LogDebug($msg) { 
    if ($VerbosePreference -eq "Continue") {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [DEBUG] $msg" -ForegroundColor Cyan 
    }
}

function LogSuccess($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [SUCCESS] $msg" -ForegroundColor Cyan 
}

function LogWarning($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [WARNING] $msg" -ForegroundColor Yellow 
}

# Funzione per trovare file credenziali
function Find-CredentialsFile() {
    $possibleFiles = @(
        "credenziali_infinity_events.json",
        ".\credenziali_infinity_events.json",
        "credenziali.json",
        ".\credenziali.json"
    )
    
    foreach ($file in $possibleFiles) {
        if (Test-Path $file) {
            Log "File credenziali trovato automaticamente: $file"
            return $file
        }
    }
    
    return $null
}

# Funzione per caricare le credenziali
function Load-Credentials($credFile) {
    try {
        if (-not (Test-Path $credFile)) {
            throw "File credenziali non trovato: $credFile"
        }
        $credentials = Get-Content $credFile -Raw | ConvertFrom-Json
        
        if (-not $credentials.clientId -or -not $credentials.accessKey) {
            throw "File credenziali non valido. Deve contenere clientId e accessKey"
        }
        
        # Gateway default Europa (identificato dal debug)
        if (-not $credentials.gateway) {
            $credentials | Add-Member -NotePropertyName "gateway" -NotePropertyValue "https://cloudinfra-gw.portal.checkpoint.com"
            LogDebug "Gateway non specificato, uso default Europa: https://cloudinfra-gw.portal.checkpoint.com"
        }
        
        return $credentials
    }
    catch {
        LogError "Errore nel caricamento delle credenziali: $($_.Exception.Message)"
        exit 1
    }
}

# Funzione per autenticazione
function Get-AuthToken($credentials) {
    try {
        Log "Autenticazione in corso..."
        
        $authUrl = "$($credentials.gateway)/auth/external"
        $authBody = @{
            clientId = $credentials.clientId
            accessKey = $credentials.accessKey
        } | ConvertTo-Json -Depth 10
        
        $authHeaders = @{
            "Content-Type" = "application/json"
        }
        
        LogDebug "POST $authUrl"
        $response = Invoke-RestMethod -Uri $authUrl -Method Post -Body $authBody -Headers $authHeaders
        
        if ($response.success -eq $true -and $response.data.token) {
            LogSuccess "Autenticazione completata con successo"
            return $response.data.token
        }
        else {
            throw "Risposta di autenticazione non valida: $($response | ConvertTo-Json)"
        }
    }
    catch {
        LogError "Autenticazione fallita: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            switch ($statusCode) {
                401 { 
                    LogError "Credenziali non valide (401 Unauthorized)"
                    LogError "Verifica che:"
                    LogError "  - Client ID e Access Key siano corretti"
                    LogError "  - L'API Key sia creata per il servizio 'Logs as a Service'"
                    LogError "  - L'API Key non sia scaduta o disabilitata"
                }
                403 { 
                    LogError "Accesso negato (403 Forbidden)" 
                    LogError "L'account potrebbe non avere i permessi necessari"
                }
                404 { 
                    LogError "Endpoint non trovato (404 Not Found)"
                    LogError "Verifica che il gateway sia corretto per la tua region"
                }
            }
        }
        exit 1
    }
}

# Funzione per creare una richiesta di ricerca log
function Start-LogsQuery($token, $gateway, $queryParams) {
    try {
        Log "Avvio ricerca log..."
        
        $queryUrl = "$gateway/app/laas-logs-api/api/logs_query"
        $queryHeaders = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        LogDebug "POST $queryUrl"
        LogDebug "Query params: $($queryParams)"
        
        $response = Invoke-RestMethod -Uri $queryUrl -Method Post -Body $queryParams -Headers $queryHeaders
        
        if ($response.success -eq $true -and $response.data.taskId) {
            Log "Task di ricerca creato: $($response.data.taskId)"
            return $response.data.taskId
        }
        else {
            throw "Risposta non valida per la creazione del task: $($response | ConvertTo-Json)"
        }
    }
    catch {
        LogError "Errore nella creazione del task di ricerca: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            switch ($statusCode) {
                400 {
                    LogError "Richiesta non valida (400 Bad Request)"
                    LogError "Possibili cause:"
                    LogError "  - Timeframe non valido o troppo ampio"
                    LogError "  - Filtro Lucene con sintassi errata"
                    LogError "  - CloudService non valido"
                    LogError "Prova senza timeframe per usare default (ultima ora)"
                }
                401 { 
                    LogError "Token scaduto o non valido" 
                    LogError "L'API Key potrebbe non avere accesso ai log"
                }
                403 { 
                    LogError "Permessi insufficienti per query sui log" 
                }
            }
        }
        exit 1
    }
}

# Funzione per controllare lo stato del task
function Get-TaskStatus($token, $gateway, $taskId) {
    try {
        $statusUrl = "$gateway/app/laas-logs-api/api/logs_query/$taskId"
        $statusHeaders = @{
            "Authorization" = "Bearer $token"
        }
        
        LogDebug "GET $statusUrl"
        $response = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers $statusHeaders
        
        if ($response.success -eq $true) {
            return $response.data
        }
        else {
            throw "Risposta non valida per il controllo dello stato: $($response | ConvertTo-Json)"
        }
    }
    catch {
        LogError "Errore nel controllo dello stato del task: $($_.Exception.Message)"
        throw
    }
}

# Funzione per recuperare i risultati paginati CON GESTIONE ERRORI MIGLIORATA
function Get-LogsResults($token, $gateway, $taskId, $pageToken) {
    try {
        $retrieveUrl = "$gateway/app/laas-logs-api/api/logs_query/retrieve"
        $retrieveHeaders = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        $retrieveBody = @{
            taskId = $taskId
            pageToken = $pageToken
        } | ConvertTo-Json -Depth 10
        
        LogDebug "POST $retrieveUrl"
        $response = Invoke-RestMethod -Uri $retrieveUrl -Method Post -Body $retrieveBody -Headers $retrieveHeaders
        
        if ($response.success -eq $true) {
            return $response.data
        }
        else {
            throw "Risposta non valida per il recupero dei risultati: $($response | ConvertTo-Json)"
        }
    }
    catch {
        # Gestione specifica per errori di paginazione
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            switch ($statusCode) {
                400 {
                    LogWarning "Errore 400 Bad Request durante il recupero pagina"
                    LogWarning "Possibili cause: pageToken scaduto, limite pagine raggiunto, o parametri non validi"
                    
                    # Restituisci un oggetto vuoto per indicare fine paginazione
                    return @{
                        records = @()
                        recordsCount = 0
                        nextPageToken = $null
                        error = "PageTokenExpired"
                    }
                }
                401 {
                    LogError "Token di autenticazione scaduto durante recupero pagina"
                    throw "Token scaduto"
                }
                default {
                    LogWarning "Errore HTTP $statusCode durante recupero pagina: $($_.Exception.Message)"
                    # Restituisci oggetto vuoto per continuare con altre pagine
                    return @{
                        records = @()
                        recordsCount = 0
                        nextPageToken = $null
                        error = "HTTPError_$statusCode"
                    }
                }
            }
        }
        else {
            LogWarning "Errore generico durante recupero pagina: $($_.Exception.Message)"
            return @{
                records = @()
                recordsCount = 0
                nextPageToken = $null
                error = "GenericError"
            }
        }
    }
}

# Funzione per attendere il completamento del task
function Wait-TaskCompletion($token, $gateway, $taskId, $pollInterval, $maxPolls) {
    $pollCount = 0
    
    while ($pollCount -lt $maxPolls) {
        $status = Get-TaskStatus -token $token -gateway $gateway -taskId $taskId
        
        Log "Stato task: $($status.state)"
        
        switch ($status.state) {
            "Ready" { 
                Log "Task pronto per il recupero"
                return $status.pageTokens
            }
            "Retrieving" {
                Log "Recupero in corso..."
                return $status.pageTokens
            }
            "Done" {
                Log "Task completato"
                if ($status.pageTokens -and $status.pageTokens.Count -gt 0) {
                    return $status.pageTokens
                }
                else {
                    Log "Nessun risultato trovato per i criteri specificati"
                    return $null
                }
            }
            "Canceled" {
                LogError "Task cancellato o errore: $($status.errors -join ', ')"
                exit 1
            }
            "Processing" {
                Log "Elaborazione in corso... (tentativo $($pollCount + 1)/$maxPolls)"
            }
            default {
                LogError "Stato task sconosciuto: $($status.state)"
                exit 1
            }
        }
        
        $pollCount++
        Start-Sleep -Seconds $pollInterval
    }
    
    LogError "Timeout raggiunto dopo $maxPolls tentativi"
    exit 1
}

# Funzione per esportare i risultati in CSV
function Export-ResultsToCSV($results, $filename) {
    try {
        Log "Esportazione risultati in CSV: $filename"
        
        # Flatten degli oggetti JSON complessi per CSV
        $flatResults = @()
        foreach ($record in $results) {
            $flatRecord = @{}
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Value -is [System.Object] -and $property.Value -isnot [string]) {
                    $flatRecord[$property.Name] = ($property.Value | ConvertTo-Json -Compress)
                }
                else {
                    $flatRecord[$property.Name] = $property.Value
                }
            }
            $flatResults += [PSCustomObject]$flatRecord
        }
        
        $flatResults | Export-Csv -Path $filename -NoTypeInformation -Encoding UTF8
        LogSuccess "Esportazione completata: $filename"
    }
    catch {
        LogError "Errore nell'esportazione CSV: $($_.Exception.Message)"
    }
}

# Script principale
try {
    Log "=== INIZIO RECUPERO LOG DA INFINITY EVENTS ==="
    
    # Trova e carica credenziali
    if ([string]::IsNullOrEmpty($CredFile)) {
        $CredFile = Find-CredentialsFile
        if ($null -eq $CredFile) {
            LogError "Nessun file credenziali trovato!"
            LogError "File cercati: credenziali_infinity_events.json, credenziali.json"
            LogError "Usa: .\GetInfinityEvents.ps1 -CredFile 'percorso_file.json'"
            exit 1
        }
    }
    
    $credentials = Load-Credentials -credFile $CredFile
    Log "Credenziali caricate da: $CredFile"
    
    # Autentica
    $token = Get-AuthToken -credentials $credentials
    
    # Prepara parametri di query (ottimizzati dai test di debug)
    $queryParams = @{
        limit = $Limit
        pageLimit = $PageLimit
    }
    
    # Aggiungi filtro se specificato
    if ($Filter) {
        $queryParams.filter = $Filter
        Log "Filtro applicato: $Filter"
    }
    
    # Aggiungi servizio cloud se specificato
    if ($CloudService) {
        $queryParams.cloudService = $CloudService  
        Log "Servizio cloud: $CloudService"
    }
    
    Log "Limite risultati: $Limit, Limite per pagina: $PageLimit"
    
    # Gestione timeframe (OPZIONALE - basato sui test di debug)
    if ($StartTime -or $EndTime) {
        $timeframe = @{}
        if ($StartTime) {
            $timeframe.startTime = $StartTime
        }
        if ($EndTime) {
            $timeframe.endTime = $EndTime
        }
        $queryParams.timeframe = $timeframe
        Log "Timeframe: $(if($StartTime){"da $StartTime"}) $(if($EndTime){"a $EndTime"})"
    }
    else {
        Log "Nessun timeframe specificato - verrà utilizzata l'ultima ora (default API)"
        Log "Questa è la configurazione più affidabile basata sui test"
    }
    
    $queryBody = $queryParams | ConvertTo-Json -Depth 10
    
    # Avvia ricerca
    $taskId = Start-LogsQuery -token $token -gateway $credentials.gateway -queryParams $queryBody
    
    # Attendi completamento
    $pageTokens = Wait-TaskCompletion -token $token -gateway $credentials.gateway -taskId $taskId -pollInterval $PollInterval -maxPolls $MaxPolls
    
    if (-not $pageTokens) {
        Log "Nessun risultato trovato"
        Log "Suggerimento: prova con un timeframe più ampio o senza filtri"
        exit 0
    }
    
    # Recupera risultati CON GESTIONE ERRORI MIGLIORATA
    $allResults = @()
    $pageCount = 0
    $totalRecordsRetrieved = 0
    $errorsEncountered = 0
    
    foreach ($pageToken in $pageTokens) {
        $pageCount++
        Log "Recupero pagina $pageCount di $($pageTokens.Count)..."
        
        $pageResults = Get-LogsResults -token $token -gateway $credentials.gateway -taskId $taskId -pageToken $pageToken
        
        # Controlla se c'è stato un errore
        if ($pageResults.error) {
            LogWarning "Errore nel recupero pagina $pageCount - $($pageResults.error)"
            $errorsEncountered++
            
            # Se è un errore di token scaduto, interrompi completamente
            if ($pageResults.error -eq "TokenScaduto") {
                LogError "Interruzione a causa di token scaduto"
                break
            }
            
            # Per altri errori, continua con la prossima pagina
            continue
        }
        
        Log "Recuperati $($pageResults.recordsCount) record da questa pagina"
        $allResults += $pageResults.records
        $totalRecordsRetrieved += $pageResults.recordsCount
        
        # Controlla se abbiamo raggiunto il limite impostato
        if ($totalRecordsRetrieved -ge $Limit) {
            Log "Raggiunto limite di $Limit record, interrompo il recupero"
            break
        }
        
        # GESTIONE PAGINAZIONE ROBUSTA
        $continuePagination = $true
        $paginationPageCount = $pageCount
        
        while ($pageResults.nextPageToken -and $continuePagination -and $totalRecordsRetrieved -lt $Limit) {
            $paginationPageCount++
            Log "Recupero pagina successiva $paginationPageCount..."
            
            $pageResults = Get-LogsResults -token $token -gateway $credentials.gateway -taskId $taskId -pageToken $pageResults.nextPageToken
            
            # Controlla errori nella paginazione
            if ($pageResults.error) {
                LogWarning "Errore durante paginazione pagina $paginationPageCount - $($pageResults.error)"
                $errorsEncountered++
                
                if ($pageResults.error -eq "PageTokenExpired" -or $pageResults.error.StartsWith("HTTPError_400")) {
                    LogWarning "PageToken scaduto o non valido, interrompo paginazione per questo token"
                    $continuePagination = $false
                    break
                }
                
                if ($pageResults.error -eq "TokenScaduto") {
                    LogError "Token di autenticazione scaduto, interrompo completamente"
                    $continuePagination = $false
                    break
                }
                
                # Per altri errori, interrompi questa catena di paginazione
                $continuePagination = $false
                break
            }
            
            if ($pageResults.recordsCount -gt 0) {
                Log "Recuperati $($pageResults.recordsCount) record da pagina successiva $paginationPageCount"
                $allResults += $pageResults.records
                $totalRecordsRetrieved += $pageResults.recordsCount
            }
            else {
                Log "Pagina $paginationPageCount vuota, fine paginazione"
                $continuePagination = $false
            }
        }
        
        # Aggiorna il conteggio delle pagine principale
        $pageCount = $paginationPageCount
    }
    
    # Mostra risultati
    Log "=== RISULTATI RECUPERO LOG ==="
    LogSuccess "Totale record recuperati: $($allResults.Count)"
    
    if ($errorsEncountered -gt 0) {
        LogWarning "Errori riscontrati durante il recupero: $errorsEncountered"
        LogWarning "Alcuni dati potrebbero essere mancanti, ma il recupero è continuato"
    }
    
    if ($allResults.Count -gt 0) {
        Log ""
        Log "Primi 5 record (esempio):"
        $allResults | Select-Object -First 5 | Format-Table -AutoSize
        
        # Esportazione CSV se richiesta
        if ($ExportCSV) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $csvFilename = "InfinityEvents_$timestamp.csv"
            Export-ResultsToCSV -results $allResults -filename $csvFilename
        }
        
        # Statistiche aggiuntive
        if ($allResults.Count -gt 0 -and $allResults[0].PSObject.Properties.Name -contains "severity") {
            Log ""
            Log "=== STATISTICHE PER SEVERITY ==="
            $severityStats = $allResults | Group-Object -Property severity | Sort-Object Count -Descending
            $severityStats | ForEach-Object {
                Log "$($_.Name): $($_.Count) eventi"
            }
        }
        
        if ($allResults.Count -gt 0 -and $allResults[0].PSObject.Properties.Name -contains "product") {
            Log ""
            Log "=== STATISTICHE PER PRODOTTO ==="
            $productStats = $allResults | Group-Object -Property product | Sort-Object Count -Descending
            $productStats | ForEach-Object {
                Log "$($_.Name): $($_.Count) eventi"
            }
        }
        
        # Statistiche timeframe se disponibili
        if ($allResults.Count -gt 0 -and $allResults[0].PSObject.Properties.Name -contains "@timestamp") {
            Log ""
            Log "=== STATISTICHE TEMPORALI ==="
            $timestamps = $allResults | ForEach-Object { $_."@timestamp" } | Sort-Object
            if ($timestamps.Count -gt 0) {
                Log "Primo evento: $($timestamps[0])"
                Log "Ultimo evento: $($timestamps[-1])"
            }
        }
    }
    
    LogSuccess "=== RECUPERO LOG COMPLETATO ==="
    
    if ($allResults.Count -gt 0) {
        Log ""
        Log "RIEPILOGO SESSIONE:"
        Log "- Record totali recuperati: $($allResults.Count)"
        Log "- Pagine elaborate: $pageCount"
        if ($errorsEncountered -gt 0) {
            Log "- Errori riscontrati: $errorsEncountered (recupero parziale)"
        }
        Log "- File credenziali: $CredFile"
        
        Log ""
        Log "SUGGERIMENTI PER USI AVANZATI:"
        Log "- Usa -Filter per ricerche specifiche: -Filter 'severity:\"Critical\" OR severity:\"High\"'"
        Log "- Usa -CloudService per filtrare per prodotto: -CloudService \"Harmony Endpoint\""
        Log "- Usa -StartTime/-EndTime per timeframe specifici (formato: 2025-10-17T00:00:00Z)"
        Log "- Usa -ExportCSV per salvare i risultati in file CSV"
        Log "- Usa -Verbose per debug dettagliato"
        Log "- Se ottieni errori di paginazione, prova a ridurre -Limit o -PageLimit"
    }
    
}
catch {
    LogError "Errore durante l'esecuzione dello script: $($_.Exception.Message)"
    LogError "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}
