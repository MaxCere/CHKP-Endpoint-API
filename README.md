# Check Point Harmony Endpoint API Scripts

This repository contains PowerShell scripts for automating Check Point Harmony Endpoint management via REST API, including endpoint operations and policy assignment analysis.

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

## ⚙️ Prerequisites

- **PowerShell 5.1** or newer
- Account with permissions on **Check Point Infinity Portal**
- API credentials (Client ID and Access Key) created in Infinity Portal
- Rights to perform endpoint operations and policy queries

## 🔧 Configuration

### 1. Credentials Setup

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

### 2. API Credentials Creation

1. Log into Check Point Infinity Portal
2. Navigate to **Global Settings** → **API Keys**
3. Create a new API Key for service: **Endpoint**
4. Copy the Client ID and Access Key to your credentials file

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

## 🐛 Troubleshooting

### Common Issues

**Authentication Failures:**
```
[ERROR] Authentication failed: (401) Unauthorized
```
- Verify Client ID and Access Key are correct
- Check that API key has Endpoint service permissions
- Ensure gateway URL is correct

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

### Debug Mode

For detailed logging, you can modify the scripts to enable debug output by changing:
```powershell
#function Log($msg)    { Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
```
to:
```powershell
function Log($msg)    { Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
```

## 📈 Advanced Usage

### Filtering Policy Results

You can modify the script to filter by specific policy families:
```powershell
# Only show Threat Prevention policies
$results | Where-Object { $_.Family -eq "Threat Prevention" }

# Only show policies with specific assignments (not global)
$results | Where-Object { $_.AssignmentType -ne "GLOBAL" }
```

### Virtual Group Analysis

Filter Virtual Group results for specific analysis:
```powershell
# Show only Virtual Groups with multiple policies
$results | Where-Object { $_.TotalPoliciesInVG -gt 1 }

# Focus on specific policy families
$results | Where-Object { $_.PolicyFamily -eq "Threat Prevention" }
```

### Automated Reporting

Combine with scheduled tasks for regular policy auditing:
```powershell
# Weekly policy assignment report
.\GetPolicyAssignments.ps1 -ExportCSV
.\GetVirtualGroupUsage.ps1 -CSVFile "Weekly_VG_Report.csv"
Send-MailMessage -To "admin@company.com" -Subject "Weekly Policy Report" -Attachments "PolicyAssignments_*.csv","Weekly_VG_Report*.csv"
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

## 📚 Related Resources

- Check Point Infinity Portal Documentation
- Harmony Endpoint API Documentation
- Check Point API Reference
- Official Python SDK

## 📋 Version History

- **v4.0 (2025-10-10)**: Added GetVirtualGroupUsage.ps1 for Virtual Group analysis
- **v3.0 (2025-10-10)**: Final working GetPolicyAssignments script with full functionality
- **v2.0 (2025-10-10)**: Added policy assignment analysis capabilities
- **v1.0**: Initial endpoint isolation/de-isolation scripts

---

## About

**Repository**: Automation scripts for Check Point Harmony Endpoint management  
**Language**: PowerShell 100.0%  
**License**: Open source  
**Maintainer**: MaxCere

### Key Features ✨

- 🔐 **Secure Authentication**: Robust auth flow with error handling
- 🎯 **Policy Analysis**: Complete visibility into policy assignments
- 🔍 **Virtual Group Insights**: Detailed Virtual Group usage analysis
- 📊 **Rich Reporting**: Console output + CSV export options
- 🔄 **Async Operations**: Handles job-based API calls properly
- 🛡️ **Error Handling**: Comprehensive error detection and reporting
- 📚 **Well Documented**: Clear usage examples and troubleshooting guides
