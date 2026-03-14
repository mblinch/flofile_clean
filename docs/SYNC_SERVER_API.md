# Preferences Sync Server API

If you host a small backend, the app can upload and download preferences so the same verbs and settings work across computers.

## Base URL

User sets one base URL in the app (e.g. `https://yourdomain.com/caption-writer-sync`). The app will call:

- `POST {baseUrl}/upload` — upload preferences
- `GET {baseUrl}/download?accountId=xxx` — download preferences for that account

## 1. Upload

- **Method:** POST  
- **URL:** `{baseUrl}/upload`  
- **Headers:** `Content-Type: application/json`  
- **Body:** Full preferences JSON (same as Export). It includes `syncAccountId` so you can store by account.

**Your server should:**  
- Parse the JSON body.  
- Use `body["syncAccountId"]` (or another agreed key) as the account key.  
- Store the whole JSON (or the parts you care about) under that account (e.g. in a DB or file).  
- Return 200 or 201.

## 2. Download

- **Method:** GET  
- **URL:** `{baseUrl}/download?accountId=xxx`  
- **Response:** 200 with body = preferences JSON (same shape as Export) for that account.

**Your server should:**  
- Read `accountId` from the query.  
- Return the stored preferences JSON for that account.  
- If no data, return 404; the app will show an error.

## Security (you decide)

- Add HTTPS.
- Optionally require a shared secret or API key (e.g. header or query param) and validate it on upload/download.
- Optionally tie `accountId` to an auth token so users only access their own data.

## Example (pseudo)

```text
POST /caption-writer-sync/upload
Body: { "version": 2, "syncAccountId": "user123", "verbSettingsBySport": { ... }, ... }

GET /caption-writer-sync/download?accountId=user123
Response: { "version": 2, "verbSettingsBySport": { ... }, ... }
```
