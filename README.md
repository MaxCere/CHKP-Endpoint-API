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
