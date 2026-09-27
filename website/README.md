# FloFile Captions — marketing website

Static site (HTML, CSS, vanilla JS) for **Namecheap shared hosting**. Upload the contents of this folder into `public_html` over SFTP. No build step.

Prepared as a functional business website for **1001746423 Ontario Inc.** (Toronto, Ontario, Canada), product **FloFile Captions**, suitable for public availability and organization verification (including Apple Developer Program).

## Pages

| Path | Purpose |
|------|---------|
| `index.html` | Home, features, company attribution |
| `about.html` | Company / product story |
| `download.html` | Platform info + early-access contact (no broken download links) |
| `privacy.html` | Privacy policy draft (PIPEDA, Firebase Google Sign-In, local photos) |
| `terms.html` | Terms of use draft |
| `contact.html` | Legal name, Toronto, mailto |
| `css/styles.css` | Dark-first theme + light mode |
| `js/main.js` | Mobile nav |
| `updates/latest.json` | App update manifest stub |
| `.htaccess` | Force HTTPS |

Privacy and terms include an HTML comment `<!-- Draft — review before publishing -->` in `<head>` (not visible on the page). Have counsel review before relying on them as final legal documents.

## Before you go live

1. Point `flofilecaptions.com` DNS at Namecheap hosting and enable SSL (AutoSSL / Let’s Encrypt).
2. Create the mailbox `dev@flofilecaptions.com` (confirm before Apple review if that is the public contact).
3. Optionally edit About copy where marked with `<!-- EDIT: ... -->` comments.
4. Replace favicon / OG image assets when you have final brand art.
5. When public builds exist, link real installer URLs on `download.html` and update `updates/latest.json`.

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
