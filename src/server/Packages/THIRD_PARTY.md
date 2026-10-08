# Vendored packages

| Module | Version | Source | License | Notes |
|---|---|---|---|---|
| `ProfileStore.luau` | 1.0.3 (commit `45c9847`, 2025-07-31) | https://github.com/MadStudioRoblox/ProfileStore | Apache-2.0 (`ProfileStore.LICENSE`) | Unmodified. Session-locked DataStore profiles used by `Services/DataService`. Audited: uses only DataStoreService, MessagingService (cross-server session-steal messages), HttpService (`GenerateGUID` only) and RunService; no HTTP requests, `loadstring` or asset loading. |
