# Sparkle release – review before commit

## Exact commands to run (after review)

```bash
# 1. Release already run; zip is at docs/FloFileBeta.zip, appcast updated.
# To commit and push:

git add docs/appcast.xml docs/FloFileBeta.zip
git commit -m 'Release 1.0.4'
git push origin main
```

## What changed in docs/appcast.xml

- **New 1.0.4 item** (top, after `</language>`) with:
  - **url:** `https://mblinch.github.io/flofile_clean/FloFileBeta.zip`
  - **length:** `38976084` (from `stat` on the signed zip)
  - **sparkle:edSignature:** from `sign_update -p` on that zip (Keychain)

Exact new item:

```xml
    <item>
      <title>Version 1.0.4</title>
      <pubDate>Thu, 12 Mar 2026 03:48:32 +0000</pubDate>
      <sparkle:version>104</sparkle:version>
      <sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>
      <enclosure
        url="https://mblinch.github.io/flofile_clean/FloFileBeta.zip"
        type="application/octet-stream"
        length="38976084" sparkle:edSignature="s1skfUia73a623xj0Y4jOI1RMYkqTl/9178vuhhhjtJcpJemiXZeghh8/CVoWFCz4th9JfbBgk6RADjIoHfSBQ==" />
    </item>
```

- Duplicate old 1.0.4 entry (releases/v1.0.4/ URL) was removed so only this item remains for 1.0.4.

## Release flow (Keychain only)

1. Build the app  
2. Zip the app → `build/release/FloFileBeta.zip`  
3. Run `sign_update -p` on that exact zip (Keychain)  
4. Copy that same zip to `docs/FloFileBeta.zip`  
5. Update `docs/appcast.xml` with the new length and `sparkle:edSignature` from step 3  
6. No `.sparkle_private_key`; no new key unless `SUPublicEDKey` in Info.plist is changed  
7. `SIGN_UPDATE` can override path (e.g. DerivedData); otherwise script uses DerivedData if found, else `tools/bin/sign_update`

## App icon not updating after install

The release script runs `generate_icons.sh` and touches the appiconset so the build gets fresh icons. If the Dock or Finder still show the old icon after an update, refresh the icon cache: run **`killall Dock`** in Terminal (or log out and back in).
