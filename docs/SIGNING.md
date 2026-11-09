# Code signing and notarization (future)

Today QuickDock is **ad-hoc signed** (`codesign --sign -`). That satisfies macOS's requirement that arm64 code
be signed and lets the App Sandbox work, but it is **not** a Developer ID signature, so Gatekeeper warns users.
Everything below is ready to switch on once the project joins the Apple Developer Program ($99/year).

## 1. Get a Developer ID certificate
1. Enroll at <https://developer.apple.com/programs/>.
2. In Xcode › Settings › Accounts (or the developer portal), create a **Developer ID Application** certificate.
3. Find its exact name: `security find-identity -v -p codesigning`
   → `Developer ID Application: Your Name (TEAMID)`.

## 2. Sign locally
```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-dmg.sh
```
`build-app.sh` already signs with the hardened runtime (`--options runtime`), the sandbox entitlements and a
secure timestamp when a real identity is given.

## 3. Notarize and staple
Create an app-specific password at <https://appleid.apple.com>, then:
```sh
xcrun notarytool store-credentials quickdock --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
xcrun notarytool submit dist/QuickDock-0.9.0-arm64.dmg --keychain-profile quickdock --wait
xcrun stapler staple dist/QuickDock-0.9.0-arm64.dmg
spctl --assess --type open --context context:primary-signature -v dist/QuickDock-0.9.0-arm64.dmg
```
Regenerate the checksum after stapling (`make-dmg.sh` does it on the next run, or `shasum -a 256`).

## 4. Automate in GitHub Actions
`.github/workflows/release.yml` signs and notarizes automatically when these repository secrets exist:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12` of the exported certificate + private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the .p12 |
| `DEVELOPER_ID_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID e-mail |
| `NOTARY_TEAM_ID` | Team ID |
| `NOTARY_APP_PASSWORD` | App-specific password |

Without them, the workflow publishes an unsigned build and adds the unsigned notice to the release notes.

## 5. After the first signed release
- Set `signed` automatically: `scripts/update-website-release.sh` detects a Developer ID signature.
- Update the website and README wording (unsigned notices, FAQ) — search for “unsigned”.
- Note for users upgrading from unsigned builds: the bundle ID stays the same, so preferences and items carry
  over. In testing, security-scoped bookmarks survived a change of ad-hoc signature (see docs/QA_REPORT.md);
  if any file shows “Needs access” after upgrading, Settings › Data › Restore File Access fixes it in one step.
