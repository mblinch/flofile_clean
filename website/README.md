# FloFile Captions — marketing website

Static site (HTML, CSS, vanilla JS) for **Namecheap shared hosting**. Upload the contents of this folder into `public_html` over SFTP. No build step.

Prepared as a functional business website for **1001746423 Ontario Inc.** (Toronto, Ontario, Canada), product **FloFile Captions**, suitable for public availability and organization verification (including Apple Developer Program).

## Pages

| Path | Purpose |
|------|---------|
| `index.html` | Home, features, company attribution |
| `about.html` | Company / product story |
| `download.html` | Google sign-in unlocks Mac beta zip download |
| `privacy.html` | Privacy policy draft (PIPEDA, Firebase Google Sign-In, local photos) |
| `terms.html` | Terms of use draft |
| `contact.html` | Legal name, Toronto, mailto |
| `admin/` | Google Sign-In + admin roster editor / jersey issues |
| `css/styles.css` | Dark-first theme + light mode |
| `css/admin.css` | Admin console layout |
| `js/main.js` | Mobile nav |
| `js/firebase-config.js` | Firebase web app config + admin emails + Mac download URL |
| `js/download-auth.js` | Download page Google sign-in gate |
| `js/admin-rosters.js` | Auth, roster CRUD, issues scan + Google search |
| `updates/latest.json` | App update manifest stub |
| `.htaccess` | Force HTTPS |

## Admin console (`/admin/`)

Signed-in Google accounts matching `FLOFILE_ADMIN_EMAILS` (same as the desktop
`AdminService`) can:

- Browse/edit Tank01 rosters (`sports_tank01/{sport}/teams/{team}/players`)
- Scan missing/duplicate jerseys
- Open Google in the default browser as `{LEAGUE} player {fullName}` (no jersey #)
- Save verified jersey numbers with `jerseySource: manual`

### Firebase setup (required once)

1. Firebase Console → Authentication → Sign-in method → enable **Google**.
2. Authentication → Settings → **Authorized domains**: add `flofilecaptions.com`
   (and `localhost` for local preview).
3. Deploy rules after changing `firestore.rules` at the repo root:

```bash
firebase deploy --only firestore:rules --project projectflo-e99c6
```

Web app already registered: **FloFile Captions Web**
(`1:737938045380:web:ae437cc9cc54b559f48c91`). Config lives in
`js/firebase-config.js`.

Privacy and terms include an HTML comment `<!-- Draft — review before publishing -->` in `<head>` (not visible on the page). Have counsel review before relying on them as final legal documents.

## Before you go live

1. Point `flofilecaptions.com` DNS at Namecheap hosting and enable SSL (AutoSSL / Let’s Encrypt).
2. Create the mailbox `dev@flofilecaptions.com` (confirm before Apple review if that is the public contact).
3. Optionally edit About copy where marked with `<!-- EDIT: ... -->` comments.
4. Replace favicon / OG image assets when you have final brand art.
5. When shipping a new Mac beta, update `FLOFILE_MAC_DOWNLOAD` in `js/firebase-config.js` and `updates/latest.json`.

Do **not** put passwords, API keys, or SFTP credentials in this repo or on the site.

## Upload via SFTP (Namecheap)

### 1. Get SFTP details (cPanel)

- Host: often `server###.web-hosting.com` or your domain  
- Port: `22` (SFTP)  
- Username: your cPanel username  
- Password or SSH key: from Namecheap / cPanel (never commit these)

### 2. Upload

Upload **everything inside** this `website/` folder into `public_html` so that `public_html/index.html` exists. Ensure `.htaccess` is uploaded (show hidden files in your SFTP client).

### 3. Verify

- `https://flofilecaptions.com/` and About / Download / Privacy / Terms / Contact  
- Footer shows **1001746423 Ontario Inc.** on every page  
- HTTP redirects to HTTPS  

## Local preview

```bash
cd website
python3 -m http.server 8080
```

Open `http://localhost:8080/`.
