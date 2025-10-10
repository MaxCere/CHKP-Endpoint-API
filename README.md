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

**Features:**
- 📋 **Complete Policy Inventory**: Lists all policy rules across all families
- 🎯 **Assignment Details**: Shows exactly which users, groups, or OUs each policy applies to
- 📊 **Rich Statistics**: Summary by family, assignment type, and top assignments
- 📁 **CSV Export**: Optional export for reporting and analysis
- 🔄 **Robust Operation**: Handles job-based API calls with automatic polling

## 🛠️ API Endpoints Used

### Authentication Flow
1. `POST /auth/external` - Initial authentication with clientId/accessKey
2. `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud` - Cloud session login

### Policy Assignment Script
- `GET /app/endpoint-web-mgmt/harmony/endpoint/api/v1/policy/metadata` - Retrieve all policy rules metadata
- `GET /app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/{jobId}` - Poll job status for async operations

### Endpoint Management Scripts
- `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/asset-management/computers/filtered` - Filter endpoints
- `POST /app/endpoint-web-mgmt/harmony/endpoint/api/v1/remediation/{action}` - Isolation operations

## 📊 Policy Assignment Analysis

The **GetPolicyAssignments.ps1** script provides comprehensive analysis:

### Assignment Types
- **ORGANIZATION_ROOT**: Policies applied to entire organization
- **VIRTUAL_GROUP**: Policies applied to specific groups
- **USER**: Policies applied to individual users (if configured)
- **ORGANIZATIONAL_UNIT**: Policies applied to specific OUs (if configured)

### Policy Families
- **General Settings**: Basic endpoint configuration
- **Threat Prevention**: Anti-malware, firewall, and security policies
- **Data Protection**: Encryption and data security policies
- **Access**: Authentication and access control policies
- **Deployment**: Installation and deployment policies
- **Agent Settings**: Endpoint agent configuration
- **Data Loss Prevention**: DLP policies
- **OneCheck**: Compliance and assessment policies

### Statistics Provided
- Total policy rules count
- Rules with specific vs. global assignments
- Distribution by policy family
- Top assigned entities
- Assignment type breakdown

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

### Automated Reporting

Combine with scheduled tasks for regular policy auditing:
```powershell
# Weekly policy assignment report
.\GetPolicyAssignments.ps1 -ExportCSV
Send-MailMessage -To "admin@company.com" -Subject "Weekly Policy Report" -Attachments "PolicyAssignments_*.csv"
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

## 📚 Related Resources

- [Check Point Infinity Portal Documentation](https://sc1.checkpoint.com/documents/Infinity_Portal/WebAdminGuides/EN/Infinity-Portal-Admin-Guide/)
- [Harmony Endpoint API Documentation](https://app.swaggerhub.com/apis/Check-Point/web-mgmt-external-api-production/1.9.221#/)
- [Check Point API Reference](https://sc1.checkpoint.com/documents/latest/APIs/)
- [Official Python SDK](https://github.com/CheckPointSW/harmony-endpoint-management-py-sdk)

## 📋 Version History

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
- 📊 **Rich Reporting**: Console output + CSV export options
- 🔄 **Async Operations**: Handles job-based API calls properly
- 🛡️ **Error Handling**: Comprehensive error detection and reporting
- 📚 **Well Documented**: Clear usage examples and troubleshooting guides