# Check Point Harmony Endpoint API Scripts

This repository contains PowerShell scripts for automating Check Point Harmony Endpoint management via REST API, including endpoint operations, policy assignment analysis, and Infinity Events log retrieval.

## 📂 Contents

### Core Scripts

- **getendpoint.ps1** 
  - Authenticates against the Infinity Portal
  - Retrieves endpoints filtered by name
  - Displays endpoint information: ID, Name, IP, Status, Isolation state

- **isolate-deisolate.ps1**
  - Toggles isolation/de-isolation for specified endpoints
  - Handles asynchronous remediation jobs with polling
  - Shows endpoint status before and after operations

- **GetPolicyAssignments.ps1** ✅ **WORKING FINAL VERSION**
  - **NEW**: Successfully retrieves all policy rules and their assignments
  - Lists every policy with detailed assignment information
  - Supports CSV export for reporting and analysis
  - Provides comprehensive statistics and summaries

- **GetVirtualGroupUsage.ps1** ✅ **NEW VIRTUAL GROUP ANALYZER**
  - **NEW**: Analyzes Virtual Group usage across all policies
  - Identifies which Virtual Groups are assigned to which policies
  - Provides detailed statistics and usage patterns
  - Exports detailed CSV reports for analysis
  - Shows policy distribution across Virtual Groups

- **GetInfinityEvents.ps1** ✅ **NEW LOGS & EVENTS RETRIEVAL**
  - **NEW**: Retrieves event logs from Check Point Infinity Events API
  - Supports all Check Point products (Harmony Endpoint, Connect, Mobile, etc.)
  - Advanced filtering with Lucene syntax and time ranges
  - Robust pagination handling with error recovery
  - CSV export functionality with detailed statistics
  - Automatic credentials detection and gateway optimization

- **TestInfinityEventsAPI.ps1** ✅ **NEW DEBUGGING TOOL**
  - **NEW**: Advanced debugging script for Infinity Events API
  - Tests multiple query formats to identify working configurations
  - Multi-region gateway testing (Europe, US)
  - Automatic gateway detection and credentials update
  - Comprehensive error diagnosis and troubleshooting

## ⚙️ Prerequisites

- **PowerShell 5.1** or newer
- Account with permissions on **Check Point Infinity Portal**
- API credentials (Client ID and Access Key) created in Infinity Portal
- Rights to perform endpoint operations, policy queries, and log access

## 🔧 Configuration

### 1. Credentials Setup for Endpoint Management

Copy the example credentials file:
```powershell
cp credenziali.json.example credenziali.json
```

Edit `credenziali.json` with your actual values:
```json
{
  "clientId": "<YourClientID>",
  "accessKey": "<YourAccessKey>",
  "gateway": "https://cloudinfra-gw.portal.checkpoint.com"
}
```

### 2. Infinity Events API Setup (for GetInfinityEvents.ps1)

Create a separate credentials file for Events API:
```json
{
  "clientId": "<YourClientID>",
  "accessKey": "<YourAccessKey>",
  "gateway": "https://cloudinfra-gw.portal.checkpoint.com"
}
```

**Note**: For Infinity Events, create API Key for service: **"Logs as a Service"**

### 3. API Credentials Creation

1. Log into Check Point Infinity Portal
2. Navigate to **Global Settings** → **API Keys**
3. Create API Keys for required services:
   - **Endpoint** - for endpoint management scripts
   - **Logs as a Service** - for Infinity Events scripts
4. Copy the Client ID and Access Key to your credentials files

## 🚀 Usage Examples

### 1. Get Endpoint Information

```powershell
# Get endpoints matching a name pattern
.\getendpoint.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```

**Output:**
```
EndpointID      Hostname        IP              IsolationStatus Groups
----------      --------        --              --------------- ------
xxx-xxx-xxx     WIN11-LAB-01    192.168.1.100   Not Isolated   Domain Computers
```

### 2. Isolate/De-isolate Endpoints

```powershell
# Toggle isolation for endpoints matching pattern
.\isolate-deisolate.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```

**Workflow:** Authenticate → Get current status → Toggle isolation → Wait for completion → Verify final state

### 3. Get Policy Assignments ✅ **NEW & WORKING**

```powershell
# Basic usage - display in console
.\GetPolicyAssignments.ps1 -CredFile ".\credenziali.json"

# Export results to CSV file
.\GetPolicyAssignments.ps1 -CredFile ".\credenziali.json" -ExportCSV

# Custom polling settings
.\GetPolicyAssignments.ps1 -CredFile ".\credenziali.json" -PollInterval 3 -MaxPolls 20
```

**Sample Output:**
```
PolicyName                          Family            AssignmentName        AssignmentType
----------                          ------            --------------        --------------
Default settings for entire org    Access            Entire Organization   ORGANIZATION_ROOT
Server Protection                  Threat Prevention  Servers              VIRTUAL_GROUP
SmartPreBoot                       Data Protection    PasswordlessPreboot  VIRTUAL_GROUP
New Rule 1                         Deployment         TEST-VG              VIRTUAL_GROUP
```

### 4. Analyze Virtual Group Usage ✅ **NEW VIRTUAL GROUP ANALYSIS**

```powershell
# Basic usage - analyze Virtual Group usage
.\GetVirtualGroupUsage.ps1 -CredFile ".\credenziali.json"

# Custom CSV output location
.\GetVirtualGroupUsage.ps1 -CredFile ".\credenziali.json" -CSVFile ".\MyVGReport.csv"
```

**Sample Output:**
```
Virtual Groups used in Policies:

VirtualGroupName    PolicyName              PolicyFamily        TotalPoliciesInVG
----------------    ----------              ------------        -----------------
PasswordlessPreboot SmartPreBoot            Data Protection     1
Servers            Server Protection        Threat Prevention   3
TEST-VG            New Rule 1              Deployment          2
TEST-VG            Custom Access Rule      Access              2

=== VIRTUAL GROUPS STATISTICS ===
Total Virtual Groups in use: 3

Virtual Groups by policy count:
  - Servers: 3 policies
  - TEST-VG: 2 policies
  - PasswordlessPreboot: 1 policies

Policy families using Virtual Groups:
  - Threat Prevention: 3 assignments
  - Deployment: 2 assignments
  - Access: 2 assignments
  - Data Protection: 1 assignments
```

### 5. Get Infinity Events ✅ **NEW LOGS RETRIEVAL**

```powershell
# Basic usage - retrieve last hour events (API default)
.\GetInfinityEvents.ps1

# Retrieve events for specific product
.\GetInfinityEvents.ps1 -CloudService "Harmony Endpoint"

# Advanced filtering with time range
.\GetInfinityEvents.ps1 -StartTime "2025-10-15T00:00:00Z" -EndTime "2025-10-17T23:59:59Z" -Filter 'severity:"High"'

# Export to CSV with custom limits
.\GetInfinityEvents.ps1 -Limit 500 -Filter 'NOT severity:"Low"' -ExportCSV

# Complex filtering examples
.\GetInfinityEvents.ps1 -Filter 'src:"192.168.1.100" AND severity:"Critical"' -ExportCSV
.\GetInfinityEvents.ps1 -Filter 'product:"Harmony Endpoint" OR product:"Harmony Connect"'
```

**Sample Output:**
```
[17:30:15] Credenziali caricate da: credenziali_infinity_events.json
[17:30:16] [SUCCESS] Autenticazione completata con successo
[17:30:16] Task di ricerca creato: abc-123-def-456
[17:30:21] Task completato
[17:30:22] Recuperati 150 record da questa pagina
[17:30:22] [SUCCESS] Totale record recuperati: 150

=== STATISTICHE PER SEVERITY ===
Critical: 25 eventi
High: 45 eventi  
Medium: 60 eventi
Low: 20 eventi

=== STATISTICHE PER PRODOTTO ===
Harmony Endpoint: 120 eventi
Harmony Connect: 30 eventi
```

### 6. Test and Debug Infinity Events API ✅ **NEW TROUBLESHOOTING**

```powershell
# Test API connectivity and find working configuration
.\TestInfinityEventsAPI.ps1

# Test with specific credentials file
.\TestInfinityEventsAPI.ps1 -CredFile ".\my_events_credentials.json"
```

**Sample Output:**
```
[17:30:10] === TEST Europe - https://cloudinfra-gw.portal.checkpoint.com ===
[17:30:11] [SUCCESS] Europe - Autenticazione riuscita
[17:30:11] Testando: Query minimale senza timeframe...
[17:30:12] [SUCCESS] SUCCESS! Task ID: xyz-789-abc-123
[17:30:15] [SUCCESS] QUERY FUNZIONANTE TROVATA ===
[17:30:15] [SUCCESS] Region: Europe
[17:30:15] [SUCCESS] Query tipo: Query minimale senza timeframe
[17:30:15] [SUCCESS] SUCCESS! L'API funziona correttamente!
```

## 🛠️ API Endpoints Used

Below are the endpoints used, including required headers, request bodies, and sample responses.

### 1) Authentication
- Endpoint: `POST /auth/external`
- Headers:
  - `Content-Type: application/json`
- Request Body:
  ```json
  {
    "clientId": "<ClientID>",
    "accessKey": "<AccessKey>"
  }
  ```
- Sample Response:
  ```json
  {
    "success": true,
    "data": {
      "token": "<jwt-token>"
    }
  }
  ```

### 2) Cloud Session Login
- Endpoint: `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud`
- Headers:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`
- Request Body:
  ```json
  {}
  ```
- Response Headers:
  - `x-mgmt-api-token: <mgmt-token>`

### 3) Policy Metadata (job-based)
- Endpoint: `GET /app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata`
- Headers:
  - `Authorization: Bearer <token>`
  - `x-mgmt-api-token: <mgmt-token>`
  - `x-mgmt-run-as-job: on`

### 4) Job Status Polling
- Endpoint: `GET /app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/{jobId}`
- Headers:
  - `Authorization: Bearer <token>`
  - `x-mgmt-api-token: <mgmt-token>`

### 5) Filter Endpoints (job-based)
- Endpoint: `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/asset-management/computers/filtered`
- Headers:
  - `Authorization: Bearer <token>`
  - `x-mgmt-api-token: <mgmt-token>`
  - `x-mgmt-run-as-job: on`
  - `Content-Type: application/json`
- Request Body:
  ```json
  {
    "filters": [
      {
        "columnName": "computerName",
        "filterValues": ["COMPUTERNAME"],
        "filterType": "Contains"
      }
    ],
    "paging": { "pageSize": 10, "offset": 0 }
  }
  ```

### 6) Remediation (isolate / de-isolate) (job-based)
- Endpoint: `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/remediation/{action}`
- Headers:
  - `Authorization: Bearer <token>`
  - `x-mgmt-api-token: <mgmt-token>`
  - `x-mgmt-run-as-job: on`
  - `Content-Type: application/json`
- Request Body (example):
  ```json
  {
    "comment": "Isolate via script",
    "timing": {
      "expirationSeconds": 1,
      "schedulingDateTime": "2025-10-17T14:30:00.000Z"
    },
    "targets": {
      "query": {
        "filter": [
          {
            "columnName": "emonJsonDataColumns",
            "filterValues": ["string"],
            "filterType": "Contains",
            "isJson": true
          }
        ],
        "paging": { "pageSize": 1, "offset": 0 }
      },
      "exclude": { "groupsIds": [], "computerIds": [] },
      "include": { "computers": [ { "id": "<endpoint-id>" } ] }
    }
  }
  ```

### 7) Infinity Events Query Creation
- Endpoint: `POST /app/laas-logs-api/api/logs_query`
- Headers:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`
- Request Body:
  ```json
  {
    "limit": 1000,
    "pageLimit": 100,
    "filter": "severity:\"High\"",
    "cloudService": "Harmony Endpoint",
    "timeframe": {
      "startTime": "2025-10-15T00:00:00Z",
      "endTime": "2025-10-17T23:59:59Z"
    }
  }
  ```

### 8) Infinity Events Task Status
- Endpoint: `GET /app/laas-logs-api/api/logs_query/{taskId}`
- Headers:
  - `Authorization: Bearer <token>`

### 9) Infinity Events Results Retrieval
- Endpoint: `POST /app/laas-logs-api/api/logs_query/retrieve`
- Headers:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`
- Request Body:
  ```json
  {
    "taskId": "<task-id>",
    "pageToken": "<page-token>"
  }
  ```

## 🐛 Troubleshooting

### Common Issues

**Authentication Failures:**
```
[ERROR] Authentication failed: (401) Unauthorized
```
- Verify Client ID and Access Key are correct
- Check that API key has correct service permissions:
  - **Endpoint** service for endpoint management
  - **Logs as a Service** for Infinity Events
- Ensure gateway URL is correct for your region

**Policy API Issues:**
```
[ERROR] Failed to request policy metadata: (403) Forbidden
```
- Verify your account has policy read permissions
- Check that you're using the correct tenant/organization

**Job Polling Timeouts:**
```
[ERROR] Job did not complete within X attempts
```
- Increase `MaxPolls` parameter for large environments
- Adjust `PollInterval` if API responses are slow

**Infinity Events API Issues:**
```
[ERROR] Errore 400 Bad Request durante creazione task
```
- Verify timeframe is not too wide (max 30 days recommended)
- Check Lucene filter syntax (use quotes for exact matches)
- Try without timeframe to use default (last hour)
- Ensure API Key has "Logs as a Service" permissions
- Use TestInfinityEventsAPI.ps1 for detailed debugging

**No Events Retrieved:**
```
[SUCCESS] Totale record recuperati: 0
```
- Check if Check Point products are sending logs to Infinity Portal
- Verify account has access to Events section in portal
- Try broader timeframe or remove filters
- Use TestInfinityEventsAPI.ps1 to test connectivity
- Check that products are properly configured and active

**Pagination Errors:**
```
[WARNING] Errore 400 Bad Request durante il recupero pagina
```
- Normal behavior when reaching end of available data
- Script automatically handles pagination errors and continues
- Consider reducing `PageLimit` if persistent issues occur

### Debug Mode

For detailed logging, you can modify the scripts to enable debug output by changing:
```powershell
#function Log($msg)    { Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
```
to:
```powershell
function Log($msg)    { Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
```

### Lucene Filter Examples for Infinity Events

```powershell
# Severity filtering
-Filter 'severity:"Critical"'
-Filter 'severity:"High" OR severity:"Critical"'
-Filter 'NOT severity:"Low"'

# Source IP filtering  
-Filter 'src:"192.168.1.100"'
-Filter 'src:"192.168.1.*"'

# Product filtering
-Filter 'product:"Harmony Endpoint"'

# Combined filters
-Filter 'severity:"High" AND src:"192.168.1.100"'
-Filter '(severity:"Critical" OR severity:"High") AND product:"Harmony Endpoint"'

# Date range with filter (alternative to StartTime/EndTime)
-Filter '@timestamp:[2025-10-15T00:00:00Z TO 2025-10-17T23:59:59Z] AND severity:"High"'
```

## 📚 Related Resources

- Check Point Infinity Portal Documentation
- Harmony Endpoint API Documentation  
- Infinity Events API Documentation
- Check Point API Reference
- Lucene Query Syntax Guide
- Official Python SDK