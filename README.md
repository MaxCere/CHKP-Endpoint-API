# Isolate-Deisolate Automation Scripts

This repository contains two PowerShell scripts for automating endpoint isolation/de-isolation operations and displaying the status of Check Point Harmony endpoints.

---

## 📂 Contents

- **GetEndpoints.ps1**  
  - Authenticates against the Infinity Portal  
  - Retrieves endpoints filtered by name  
  - Prints a table with columns: `ID`, `Name`, `IP`, `Status`, `Isolation`

- **isolate-deisolate.ps1**  
  - Toggles isolation/de-isolation for a specified endpoint  
  - Waits for asynchronous remediation jobs to complete  
  - Shows endpoint status before and after the operation  

---

## ⚙️ Prerequisites

- **PowerShell 5.1** or newer  
- Account with permissions on **Check Point Infinity Portal**  
- API Key created in the Infinity Portal (service: **Endpoint**)  
- Rights to perform endpoint isolation  

---

## 🔧 Configuration

1. Copy the example credentials file:  
   ```bash
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

---

## 🧭 Script Flow

1. **Authenticate**  
   - POST to `<gateway>/auth/external` with `clientId` and `accessKey`  
   - Receive bearer token  
2. **Cloud Login**  
   - POST to `<gateway>/.../v1/session/login/cloud` with bearer token  
   - Receive `x-mgmt-api-token` header  
3. **Initial State**  
   - POST to `/v1/asset-management/computers/filtered` to submit filter job  
   - Poll `/v1/jobs/{jobId}` until status is `DONE`  
   - Extract and display endpoint table  
4. **Toggle Remediation**  
   - Determine action (`isolate` or `de-isolate`) based on current isolation state  
   - POST to `/v1/remediation/{action}` with job header  
   - Poll `/v1/jobs/{jobId}` until status is `DONE`  
5. **Final State**  
   - Loop: re-run filtered job and poll until endpoint’s `Isolation` field flips  
   - Display updated endpoint table  

---

## 🚀 Usage Examples

### 1. GetEndpoints.ps1

```powershell
.\GetEndpoints.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```
Retrieves and prints a table of endpoints whose names contain `Win11-LAB`.

### 2. isolate-deisolate.ps1

```powershell
.\isolate-deisolate.ps1 -CredFile ".\credenziali.json" -FilterName "Win11-LAB"
```

**Workflow**: follow the Script Flow above to authenticate, submit jobs, poll status, toggle isolation, and verify final state.

---

## 🛠️ Logging & Debug

- `[DEBUG]` – progress details, job IDs, statuses  
- `[ERROR]` – authentication errors, polling failures, rate limits  

---

## 🤝 Contributing

Pull requests and issues are welcome!  

---
