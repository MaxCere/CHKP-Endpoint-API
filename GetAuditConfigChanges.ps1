# GetAuditConfigChanges.ps1 - Check Point Audit/Configuration Changes Extractor

Extracts audit and configuration change events from Check Point Infinity Events API.

## Usage
```powershell
# Basic usage (last 24h)
.\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json

# Custom time range
.\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json -StartTime "2025-10-15T00:00:00Z" -EndTime "2025-10-17T23:59:59Z" -ExportCSV

# With additional filter
.\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json -Filter 'user:"admin"' -ExportCSV
```

## Parameters
- `-CredFile` Path to credentials JSON
- `-StartTime`/`-EndTime` ISO8601 timestamps
- `-Filter` Additional Lucene filter
- `-Limit` Max records (default: 1000)
- `-ExportCSV` Export to CSV
- `-Debug` Enable debug logging

See [PRD](GetAuditConfigChanges-PRD.md) for full specification.