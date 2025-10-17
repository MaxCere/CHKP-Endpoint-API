<#
.SYNOPSIS
    Script di debug avanzato con test query multiple per API Infinity Events

.DESCRIPTION
    Test multipli con diversi formati di query per identificare il problema esatto

.PARAMETER CredFile
    Percorso al file JSON delle credenziali (opzionale)

.EXAMPLE
    .\AdvancedDebugInfinityEventsAPI.ps1

.NOTES
    Versione: 1.2
    Autore: MaxCere
    Data: 2025-10-17
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CredFile = ""
)

function Log($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Green 
}

function LogError($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] $msg" -ForegroundColor Red 
}

function LogWarning($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [WARNING] $msg" -ForegroundColor Yellow 
}

function LogSuccess($msg) { 
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [SUCCESS] $msg" -ForegroundColor Cyan 
}

function Find-CredentialsFile() {
    $possibleFiles = @(
        "credenziali_infinity_events.json",
        ".\credenziali_infinity_events.json",
        "credenziali.json",
        ".\credenziali.json"
    )
    
    foreach ($file in $possibleFiles) {
        if (Test-Path $file) {
            LogSuccess "File credenziali trovato automaticamente: $file"
            return $file
        }
    }
    
    return $null
}

function Test-MultipleQueryFormats($gateway, $token) {
    Log ""
    Log "=== TEST MULTIPLE QUERY FORMATS ==="
    
    $queryUrl = "$gateway/app/laas-logs-api/api/logs_query"
    $queryHeaders = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    # Array di query da testare
    $testQueries = @(
        @{
            "name" = "Query minimale senza timeframe"
            "body" = @{
                limit = 10
                pageLimit = 10
            }
        },
        @{
            "name" = "Query con timeframe ultima ora"
            "body" = @{
                limit = 10
                pageLimit = 10
                timeframe = @{
                    startTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        },
        @{
            "name" = "Query con timeframe ultimo giorno"
            "body" = @{
                limit = 10
                pageLimit = 10
                timeframe = @{
                    startTime = (Get-Date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        },
        @{
            "name" = "Query con cloudService specificato"
            "body" = @{
                limit = 10
                pageLimit = 10
                cloudService = "Harmony Endpoint"
                timeframe = @{
                    startTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        },
        @{
            "name" = "Query senza limit/pageLimit"
            "body" = @{
                timeframe = @{
                    startTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        },
        @{
            "name" = "Query con solo limit"
            "body" = @{
                limit = 100
            }
        }
    )
    
    foreach ($testQuery in $testQueries) {
        Log "Testando: $($testQuery.name)..."
        
        $queryBody = $testQuery.body | ConvertTo-Json -Depth 10
        Log "Body: $queryBody"
        
        try {
            $response = Invoke-RestMethod -Uri $queryUrl -Method Post -Body $queryBody -Headers $queryHeaders -TimeoutSec 15
            
            if ($response.success -eq $true -and $response.data.taskId) {
                LogSuccess "SUCCESS! Task ID: $($response.data.taskId)"
                return @{
                    "queryName" = $testQuery.name
                    "taskId" = $response.data.taskId
                    "queryBody" = $queryBody
                }
            } else {
                LogWarning "Response success false o taskId mancante"
                Log "Response: $($response | ConvertTo-Json -Depth 3)"
            }
        }
        catch {
            try {
                $statusCode = $_.Exception.Response.StatusCode.Value__
                LogWarning "Errore $statusCode per query: $($testQuery.name)"
                
                # Leggi response body dettagliato
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                if ($responseBody) {
                    LogWarning "Response body: $responseBody"
                }
            }
            catch {
                LogWarning "Errore generico per query: $($testQuery.name) - $($_.Exception.Message)"
            }
        }
        
        Log ""
    }
    
    return $null
}

try {
    Log "=== DEBUG AVANZATO CON QUERY MULTIPLE ==="
    
    # Trova file credenziali
    if ([string]::IsNullOrEmpty($CredFile)) {
        $CredFile = Find-CredentialsFile
        if ($null -eq $CredFile) {
            LogError "Nessun file credenziali trovato!"
            exit 1
        }
    }
    
    $credentials = Get-Content $CredFile -Raw | ConvertFrom-Json
    
    Log "=== INFORMAZIONI CREDENZIALI ==="
    Log "File: $CredFile"
    Log "Client ID: $($credentials.clientId)"
    Log "Access Key: $($credentials.accessKey.Substring(0,8))..."
    
    # Test solo Europa e US visto che sono quelli che autenticano
    $workingGateways = @{
        "Europe" = "https://cloudinfra-gw.portal.checkpoint.com"
        "US" = "https://cloudinfra-gw-us.portal.checkpoint.com"
    }
    
    foreach ($region in $workingGateways.Keys) {
        $gateway = $workingGateways[$region]
        
        Log ""
        Log "=== TEST $region - $gateway ==="
        
        # Autentica
        try {
            $authUrl = "$gateway/auth/external"
            $authBody = @{
                clientId = $credentials.clientId
                accessKey = $credentials.accessKey
            } | ConvertTo-Json -Depth 10
            
            $authHeaders = @{
                "Content-Type" = "application/json"
            }
            
            $response = Invoke-RestMethod -Uri $authUrl -Method Post -Body $authBody -Headers $authHeaders -TimeoutSec 10
            
            if ($response.success -eq $true -and $response.data.token) {
                LogSuccess "$region - Autenticazione riuscita"
                $token = $response.data.token
                
                # Test query multiple
                $workingQuery = Test-MultipleQueryFormats $gateway $token
                
                if ($workingQuery) {
                    Log ""
                    LogSuccess "=== QUERY FUNZIONANTE TROVATA ==="
                    LogSuccess "Region: $region"
                    LogSuccess "Gateway: $gateway"
                    LogSuccess "Query tipo: $($workingQuery.queryName)"
                    LogSuccess "Task ID: $($workingQuery.taskId)"
                    Log "Query body: $($workingQuery.queryBody)"
                    
                    # Aggiorna file credenziali
                    $credentials.gateway = $gateway
                    $credentials | ConvertTo-Json -Depth 10 | Set-Content $CredFile -Encoding UTF8
                    LogSuccess "File credenziali aggiornato"
                    
                    # Test stato task
                    Log ""
                    Log "=== TEST STATO TASK ==="
                    
                    $statusUrl = "$gateway/app/laas-logs-api/api/logs_query/$($workingQuery.taskId)"
                    $statusHeaders = @{
                        "Authorization" = "Bearer $token"
                    }
                    
                    try {
                        Start-Sleep -Seconds 3
                        $statusResponse = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers $statusHeaders -TimeoutSec 15
                        
                        if ($statusResponse.success -eq $true) {
                            LogSuccess "Controllo stato completato"
                            Log "Stato: $($statusResponse.data.state)"
                            
                            if ($statusResponse.data.pageTokens -and $statusResponse.data.pageTokens.Count -gt 0) {
                                LogSuccess "Page tokens: $($statusResponse.data.pageTokens.Count)"
                            }
                        }
                    }
                    catch {
                        LogWarning "Errore controllo stato: $($_.Exception.Message)"
                    }
                    
                    Log ""
                    LogSuccess "=== CONFIGURAZIONE FINALE ==="
                    LogSuccess "Gateway: $gateway"
                    LogSuccess "Region: $region"
                    LogSuccess "Query funzionante: $($workingQuery.queryName)"
                    Log ""
                    LogSuccess "SUCCESS! L'API funziona correttamente!"
                    
                    exit 0
                }
            }
        }
        catch {
            LogWarning "$region - Errore autenticazione: $($_.Exception.Message)"
        }
    }
    
    LogError ""
    LogError "=== NESSUNA QUERY FUNZIONANTE ==="
    LogError "Tutte le query testate hanno fallito."
    LogError ""
    LogError "Possibili cause specifiche:"
    LogError "1. Account non ha accesso ai dati di log (nessun evento disponibile)"
    LogError "2. Timeframe troppo ristretto (nessun evento nell'ultima ora/giorno)"  
    LogError "3. Prodotti Check Point non configurati o attivi"
    LogError "4. API Key con permessi limitati"
    LogError ""
    LogError "AZIONI CONSIGLIATE:"
    Log "1. Verifica nel portale Infinity se ci sono eventi nella sezione Events"
    Log "2. Prova con un timeframe più ampio (ultima settimana/mese)"
    Log "3. Controlla che i prodotti Check Point stiano inviando log"
    Log "4. Verifica che l'account abbia accesso alla sezione Events nel portale"
    
} catch {
    LogError "Errore critico: $($_.Exception.Message)"
    LogError "Stack trace: $($_.Exception.StackTrace)"
}
