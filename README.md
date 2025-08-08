Isolate-Deisolate Automation Scripts

Questo repository contiene due script PowerShell per l'automazione delle operazioni di endpoint isolation/de-isolation e la visualizzazione dello stato degli endpoint Check Point Harmony.

Contenuto

GetEndpoints.ps1: Script che si autentica presso l'Infinity Portal, recupera la lista degli endpoint filtrati per nome, e stampa una tabella con ID, Nome, IP, Status e Isolation.

isolate-deisolate.ps1: Script avanzato (versione fissa) che alterna l'isolamento/de-isolamento di un endpoint specifico, attende il completamento dei job asincroni e ne mostra lo stato prima e dopo.

Prerequisiti

PowerShell 5.1 o superiore

Accesso a Check Point Infinity Portal e Harmony Endpointmgmt API

API Key creata nel portale Infinity (servizio Endpoint)

Permessi adeguati per eseguire operazioni di isolamento

Configurazione

Copiare credenziali.json.example in credenziali.json e inserire:

{
  "clientId": "<YourClientID>",
  "accessKey": "<YourAccessKey>",
  "gateway": "https://<your-infinity-gateway>"
}

Personalizzare i parametri se necessario:

$FilterName: nome (o parte) dell'endpoint da filtrare

$PageSize, $PollInterval, $MaxPolls: controllano il polling

Uso degli script

GetEndpoints.ps1

.\GetEndpoints.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"

Stampa la tabella iniziale degli endpoint corrispondenti al filtro.

isolate-deisolate.ps1

.\isolate-deisolate.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"

Flusso operativo:

Autenticazione e login cloud

Recupero stato iniziale degli endpoint

Toggle (isolate/de-isolate) sull'endpoint principale

Polling dei job di remediation finché non risultano DONE

Loop finale: polling dello stato dell'endpoint finché non cambia isolamento

Stampa tabella finale con nuovo stato

Logging e Debug

Entrambi gli script emettono logging in console:

[DEBUG]: informazioni di avanzamento, job ID, status

[ERROR]: errori di autenticazione, poll, api, rate limit

Contribuire

PR e segnalazioni di issue sono benvenute.
