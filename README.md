# Isolate-Deisolate Automation Scripts

This repository contains PowerShell scripts for automating endpoint isolation/de-isolation operations and policy management for Check Point Harmony endpoints.

## 📂 Contents

- **GetEndpoints.ps1** (now: **getendpoint.ps1**)
  - Authenticates against the Infinity Portal
  - Retrieves endpoints filtered by name
  - Prints a table with columns: `ID`, `Name`, `IP`, `Status`, `Isolation`

- **isolate-deisolate.ps1**
  - Toggles isolation/de-isolation for a specified endpoint
  - Waits for asynchronous remediation jobs to complete
  - Shows endpoint status before and after the operation

- **GetPolicyAssignments.ps1** ⭐ **NEW**
  - Retrieves all policy rules from Harmony Endpoint
  - For each policy rule, lists all entities (users, groups, OUs) to which it's assigned
  - Provides detailed assignment information and summary statistics
  - Supports both direct API calls and job-based operations

## ⚙️ Prerequisites

- **PowerShell 5.1** or newer
- Account with permissions on **Check Point Infinity Portal**
- API Key created in the Infinity Portal (service: **Endpoint**)
- Rights to perform endpoint isolation and policy queries

## 🔧 Configuration

1. Copy the example credentials file:
   ```powershell
   cp credenziali.json.example credenziali.json
   ```

2. Edit `credenziali.json` with your values:
   ```json
   {
     "clientId": "<YourClientID>",
     "accessKey": "<YourAccessKey>",
     "gateway": "https://<your-infinity-gateway>"
   }
   ```

3. (Optional) Adjust internal script parameters:
   - `$FilterName` – endpoint name or pattern
   - `$PageSize`, `$PollInterval`, `$MaxPolls` – polling settings

## 🧭 Script Flow

1. **Authenticate** - POST to `<gateway>/auth/external` with `clientId` and `accessKey`
   - Receive bearer token
2. **Cloud Login** - POST to `<gateway>/.../v1/session/login/cloud` with bearer token
   - Receive `x-mgmt-api-token` header
3. **API Operations** - Use management token for subsequent API calls
4. **Job Management** - Handle asynchronous operations with polling

## 🚀 Usage Examples

### 1. GetEndpoints (getendpoint.ps1)

```powershell
.\getendpoint.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```

Retrieves and prints a table of endpoints whose names contain `Win11-LAB`.

### 2. Isolate/De-isolate Endpoint

```powershell
.\isolate-deisolate.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```

**Workflow**: Authenticate → Get endpoint status → Toggle isolation → Verify final state.

### 3. Get Policy Assignments ⭐ **NEW**

```powershell
.\GetPolicyAssignments.ps1 -CredFile ".\credenziali.json"
```

**Features**:
- Lists all policy rules in your Harmony Endpoint environment
- Shows which entities (users, groups, OUs) each policy is assigned to
- Provides summary statistics
- Handles both direct API responses and job-based operations
- Supports various rule types (Firewall, Anti-Malware, etc.)

**Output Example**:
```
RuleID    RuleName                    RuleType     Domain   Assignments                           AssignmentCount
------    --------                    --------     ------   -----------                           ---------------
rule-001  Default Firewall Rule       Firewall     Global   No specific assignments (applies...   0
rule-002  Sales Team Protection       Anti-Malware Global   Sales OU (ORGANIZATIONAL_UNIT); ...  2
rule-003  Developer Workstations      Firewall     Global   Developers (AD_GROUP)                1
```

**Summary Information**:
- Total number of rules
- Rules with specific assignments vs. global rules
- Rules grouped by type (Firewall, Anti-Malware, etc.)

### 4. Advanced Parameters

```powershell
# Custom polling settings
.\GetPolicyAssignments.ps1 -CredFile ".\credenziali.json" -PageSize 100 -PollInterval 3 -MaxPolls 20
```

## 🛠️ API Endpoints Used

### Policy Assignment Script
- `GET /v1/policy/rule-metadata` - Retrieve all policy rules
- `GET /v1/policy/rule-metadata/{ruleId}/assignments` - Get assignments for specific rule
- `GET /v1/jobs/{jobId}` - Poll job status for async operations

### Endpoint Management Scripts
- `POST /v1/asset-management/computers/filtered` - Filter endpoints
- `POST /v1/remediation/{action}` - Isolate/de-isolate operations

## 🛠️ Logging & Debug

- `[INFO]` – Progress details, job IDs, statuses
- `[SUCCESS]` – Completed operations, summaries
- `[ERROR]` – Authentication errors, polling failures, rate limits

## 📊 Policy Assignment Features

The new **GetPolicyAssignments.ps1** script provides:

1. **Comprehensive Policy Discovery**
   - Retrieves all policy rules across all rule types
   - Supports Firewall, Anti-Malware, Application Control, and other policy types

2. **Assignment Details**
   - Shows specific users, groups, or organizational units assigned to each rule
   - Differentiates between global rules and specifically assigned rules
   - Displays assignment types (e.g., AD_GROUP, ORGANIZATIONAL_UNIT, USER)

3. **Flexible Operation Modes**
   - Attempts direct API calls first for better performance
   - Falls back to job-based operations for large datasets
   - Handles API rate limiting and timeouts gracefully

4. **Rich Output and Statistics**
   - Tabular display with sorting and formatting
   - Summary statistics and rule distribution
   - Clear indication of rules that apply to all vs. specific assignments

## 🤝 Contributing

Pull requests and issues are welcome!

## 🔗 Related Resources

- [Check Point Infinity Portal Administration Guide](https://sc1.checkpoint.com/documents/Infinity_Portal/WebAdminGuides/EN/Infinity-Portal-Admin-Guide/)
- [Harmony Endpoint API Documentation](https://app.swaggerhub.com/apis/Check-Point/web-mgmt-external-api-production)
- [Check Point API Reference](https://sc1.checkpoint.com/documents/latest/APIs/)

---

## About

Automation scripts for Check Point Harmony Endpoint management via REST API.

### Languages
- PowerShell 100.0%