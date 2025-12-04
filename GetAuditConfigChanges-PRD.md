# GetAuditConfigChanges.ps1 - Product Requirements Document (PRD)

## Objective

Create a PowerShell script that uses the Check Point Infinity Events “Logs as a Service” API to extract audit/configuration‑change logs and produce a report suitable for tracking who changed what, where, and when in the security configuration. The script should be aligned with the patterns used in `GetInfinityEvents.ps1` in the CHKP‑Endpoint‑API repository and be easy to schedule or integrate into existing operations. [README](https://github.com/MaxCere/CHKP-Endpoint-API/blob/main/README.md)

## Scope and Use Cases

- Retrieve audit/configuration‑change events from Infinity Events for:
  - Policy changes (create/modify/delete rules, policy activation).
  - Object changes (hosts, groups, virtual groups, users, etc.).
  - Global or tenant settings changes.
- Typical use cases:
  - Daily export of configuration changes for internal change tracking.
  - On‑demand extraction for incident review (“what changed before this incident?”).
  - Feeding SIEM/BI with normalized configuration‑change data.

**Out of scope:**
- Real‑time streaming or webhooks.
- Direct modification of any configuration; this script is read‑only.

## Functional Requirements

### Inputs and Parameters

The script (e.g. `GetAuditConfigChanges.ps1`) must support:

- `-CredFile <path>`  
  Path to JSON credentials file for Logs as a Service, same structure used by `GetInfinityEvents.ps1`:  
  `clientId`, `accessKey`, `gateway`. [README](https://github.com/MaxCere/CHKP-Endpoint-API/blob/main/README.md)

- Time selection (mutually combinable as in `GetInfinityEvents.ps1`):
  - `-StartTime <ISO8601>` (e.g. `2025-10-15T00:00:00Z`)
  - `-EndTime <ISO8601>`
  - If none provided, default to a configurable relative window (e.g. last 24h).

- Filtering:
  - `-Filter <string>` optional Lucene filter to further narrow down audit logs (user, object, policy, severity, etc.).
  - The script should automatically apply a **base filter** that restricts events to configuration/audit changes (e.g. by product, eventType or category), while still allowing the user to add more conditions.

- Limits:
  - `-Limit <int>` total maximum records to retrieve (default similar to `GetInfinityEvents.ps1`, e.g. 1000).
  - `-PageLimit <int>` per‑page record limit for `/logs_query` (e.g. 100).

- Output:
  - `-ExportCSV` switch to export results to CSV.
  - `-CSVFile <path>` optional, custom output file path (default to timestamped filename).
  - `-RawJSONFile <path>` optional, to dump the raw JSON records for further processing.
  - `-Quiet` optional, reduces console verbosity (only errors and key summary).

- Tuning & diagnostics:
  - `-PollInterval <int>` seconds between task‑status polls.
  - `-MaxPolls <int>` max number of polls before timeout.
  - `-Debug` switch to enable detailed logging (similar to README suggestion for debug function).

### Authentication and API Use

- Reuse the Infinity Events “Logs as a Service” flow already documented:
  - `POST /auth/external` with `clientId` and `accessKey` to get the bearer token.  
  - `POST /app/laas-logs-api/api/logs_query` to create the search task (using `limit`, `pageLimit`, `filter`, `cloudService`, `timeframe`).  
  - `GET /app/laas-logs-api/api/logs_query/{taskId}` to poll task status until `state = "Ready"` and retrieve `pageTokens`.  
  - `POST /app/laas-logs-api/api/logs_query/retrieve` to fetch records for each `pageToken`. [README](https://github.com/MaxCere/CHKP-Endpoint-API/blob/main/README.md)

- Use the same gateway and credentials conventions as `GetInfinityEvents.ps1`.

### Audit‑Specific Logic

- **Default base filter** must target audit/configuration‑change logs, for example:
  - product / service that generates audit events, and/or
  - event category / type for configuration changes.
- Allow the user filter to be combined with the base filter, e.g.:  
  `(<base-audit-filter>) AND (<user-filter>)`.

- From each record, derive/normalize at least:
  - `Timestamp` (event time).
  - `User` (who made the change).
  - `ActionType` (e.g. policy‑update, object‑create, object‑delete, settings‑change).
  - `ObjectName` and `ObjectType` (rule, policy, host, group, profile, etc., where available).
  - `Source` (management / product context).
  - `Result` or `Status` (success/failure if present).
  - `OriginalEventId` or similar identifier for traceability.

- If the JSON structure is heterogeneous, the script should:
  - Try to map common fields.
  - Preserve the full record in a raw JSON field when exporting CSV (optional) or offer a `-RawJSONFile` dump.

### Output and Reporting

**Console:**
- Progress messages similar to `GetInfinityEvents.ps1`:
  - Credentials file used.
  - Authentication success.
  - Task creation and completion.
  - Number of records per page and total.
- **Summary section**, for example:
  - Total configuration‑change events retrieved.
  - Events per `User`.
  - Events per `ActionType`.
  - Events per day in the selected window.

**CSV export:**
- Columns at minimum:  
  `Timestamp, User, ActionType, ObjectType, ObjectName, Source, Result, Severity, EventId` plus a generic `RawDetails` or similar for extra data.
- Use UTF‑8 encoding and standard separators (`,`).
- Handle missing fields gracefully (empty cells).

**Error handling:**
- Authentication errors: clear message and exit code.
- Bad request (400) on query or pagination: honor the same behavior as in the README (pagination errors can be normal at end of data; script should log a warning and stop that page). [README](https://github.com/MaxCere/CHKP-Endpoint-API/blob/main/README.md)
- Task timeouts: indicate which taskId failed and suggestion to adjust `MaxPolls`/`PollInterval`.

## Non‑Functional Requirements

- **Technology:** PowerShell (same baseline as existing scripts, e.g. 5.1+).
- **Style:**
  - Follow naming and structure conventions used by `GetInfinityEvents.ps1` in this repo (functions for `Authenticate`, `CreateLogsQuery`, `WaitForTaskReady`, `RetrievePages`, `ExportCSV`, etc.).
  - Support running from Windows and from PowerShell Core on other OSes where possible.
- **Performance:**
  - Efficient pagination using `pageTokens` and `nextPageToken` as in the README.  
  - Reasonable defaults so that typical daily windows complete within a few minutes in medium environments.
- **Localization:**
  - Log messages can stay consistent with existing scripts (Italian/English mix is acceptable as in README examples), but key field names in CSV should be English and stable.

## User Flow

1. Administrator prepares a credentials file for Logs as a Service (or reuses the one from `GetInfinityEvents.ps1`).  
2. Runs, for example:  
   ```powershell
   .\GetAuditConfigChanges.ps1 -CredFile .\credenziali_infinity_events.json -StartTime "2025-10-15T00:00:00Z" -EndTime "2025-10-17T23:59:59Z" -ExportCSV
   ```
3. Script:
   - Authenticates via `/auth/external`.  
   - Builds a logs query with a base audit filter and given timeframe.  
   - Creates the task on `/logs_query`, polls `/logs_query/{taskId}` until `Ready`, then retrieves all pages with `/logs_query/retrieve`.  
   - Aggregates and normalizes records, exports them to CSV and prints summary stats.  
4. Administrator reviews CSV to see all configuration changes (who/what/when) and optionally loads it into SIEM/BI.

## Acceptance Criteria

- Script runs using the same credential model and gateway as `GetInfinityEvents.ps1` without modifications to existing files. [README](https://github.com/MaxCere/CHKP-Endpoint-API/blob/main/README.md)
- With no parameters except `-CredFile`, script:
  - Uses a default timeframe (e.g. last 24h) and default audit base filter.
  - Retrieves at least some audit/configuration‑change events in an environment where such events exist.
  - Produces a CSV with the required columns.
- When `-Filter`, `-StartTime`, `-EndTime`, `-Limit`, `-ExportCSV`, `-CSVFile` are used, behavior matches the expectations:
  - Time range respected.
  - Filters applied on top of base audit filter.
  - Limits and pagination honored.
  - Correct CSV generated at requested path.
- Error scenarios (wrong credentials, wrong gateway, invalid filter syntax, timeout) produce clear messages and non‑zero exit codes, without partial or corrupt CSV output.