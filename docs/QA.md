# Quality Assurance & Manual Test Matrix (QA.md)

This document outlines the systematic manual testing procedures for Filo across all operating environments and edge conditions.

---

## 1. Authentication & Security Lock Test Matrix

| Test ID | Scenario | Steps to Reproduce | Expected Result | Pass/Fail |
|---|---|---|---|---|
| AUTH-01 | Fresh Onboarding & Explanations | Launch app on clean install. Review introductory slides. | Clear explanation of zero-knowledge, no-server architecture. | Pending |
| AUTH-02 | Telegram Phone Login | Enter valid phone number with international country code. Receive and input SMS/Telegram verification code. | Transition to 2FA password screen (if enabled) or passphrase creation. | Pending |
| AUTH-03 | Two-Factor Authentication (2FA) | Enter correct Telegram 2FA cloud password. | Telegram session establishes; private vault channel checks. | Pending |
| AUTH-04 | 2FA Invalid Password | Enter incorrect 2FA password. | Clear error feedback without app crash or credential leak. | Pending |
| AUTH-05 | Passphrase Creation & Strength Meter | Type passwords of varying strength (weak, medium, strong, very strong). | Visual meter updates dynamically; enforces minimum length and entropy. | Pending |
| AUTH-06 | Permanent Loss Warning Confirmation | Attempt to proceed without ticking explicit confirmation check. | Button disabled until user explicitly confirms understanding that lost passphrase cannot be recovered. | Pending |
| AUTH-07 | Recovery Key Export | Generate recovery key. Export/Copy to secure location. | BIP39 or hex recovery phrase displayed clearly with copy affordance. | Pending |
| AUTH-08 | Biometric Lock Setup | Enable FaceID/Fingerprint lock in Settings. Set timeout to immediate. | App locks when backgrounded; unlocks seamlessly with biometrics. | Pending |
| AUTH-09 | App Switcher Privacy Blur | Move app to background while displaying confidential document. Inspect OS app switcher. | App screen is obfuscated/blurred; no plaintext contents visible in task switcher preview. | Pending |
| AUTH-10 | Logout & Local Data Wipe | Navigate to Settings > Danger Zone > Wipe Local Data. Confirm destructive modal. | All local SQLite databases, secure storage tokens, and caches erased. App restarts to welcome screen. | Pending |

---

## 2. File Operations & Virtual Hierarchy Test Matrix

| Test ID | Scenario | Steps to Reproduce | Expected Result | Pass/Fail |
|---|---|---|---|---|
| FILE-01 | Create Virtual Folder | Tap "+" FAB > "New Folder" > Enter "Documents". | New folder appears instantly in UI with spring animation. | Pending |
| FILE-02 | Nested Virtual Folders | Open "Documents" folder. Create "Tax 2026". | Breadcrumb/navigation updates; path hierarchy maintained. | Pending |
| FILE-03 | Rename Folder & File | Long press folder/file > Tap "Rename" > Change name. | Updates smoothly in local SQLite index; sync state updated. | Pending |
| FILE-04 | Move File between Folders | Select file > "Move" > Choose target folder. | Node parent ID updated; file relocates instantly in UI. | Pending |
| FILE-05 | Favorite / Star Toggle | Tap star icon on file card or in context menu. | Item reflects favorite status; appears in "Favorites" filter. | Pending |
| FILE-06 | Multi-Select Batch Actions | Long press to enter multi-select mode. Select 5 files. Tap Delete. | Confirmation bottom sheet appears; selected files moved to Trash together. | Pending |
| FILE-07 | Trash & 30-Day Restore | Move file to Trash. Open "Trash" tab. Tap "Restore". | File restored to original parent directory; `is_trashed` set to 0. | Pending |
| FILE-08 | Permanent Delete | Open Trash > Tap "Empty Trash" or delete individual item. | Telegram document messages deleted; chunks removed from local DB. | Pending |

---

## 3. Transfer Engine, Chunking & Resiliency Test Matrix

| Test ID | Scenario | Steps to Reproduce | Expected Result | Pass/Fail |
|---|---|---|---|---|
| TRANS-01 | Upload Small File (<10 MB) | Select image/PDF from file picker. | Upload finishes in single chunk; progress ring animates smoothly. | Pending |
| TRANS-02 | Upload Large File (>1 GB) | Select 1.5 GB 4K video file. | File sliced into 32MB chunks; uploaded sequentially or concurrently (max 3); memory remains < 120MB. | Pending |
| TRANS-03 | Duplicate File Detection | Re-upload identical file. | Content hash matches existing node; alerts user or references existing chunks without re-uploading. | Pending |
| TRANS-04 | Network Interruption Mid-Upload | Start 500 MB upload. Toggle Airplane mode at 50%. | Transfer pauses cleanly with "Waiting for network"; no crash. | Pending |
| TRANS-05 | Network Restoration & Auto-Resume | Disable Airplane mode. | Transfer resumes automatically from the last uncommitted chunk. | Pending |
| TRANS-06 | App Termination Mid-Transfer | Kill app process via OS task manager while upload is at 40%. Re-launch app. | Queue displays paused or auto-resuming task at 40%; completed chunks are not re-uploaded. | Pending |
| TRANS-07 | Telegram Flood-Wait (Rate Limit) | Trigger flood wait (e.g. rapid succession calls). | App catches flood-wait exception; displays friendly cooldown timer ("Waiting 15s to resume..."); resumes automatically. | Pending |
| TRANS-08 | Low Device Storage | Attempt download when device free space < file size. | Graceful error: "Insufficient device storage"; transfer halts before writing. | Pending |

---

## 4. Media Previews & Decrypting Streaming Proxy

| Test ID | Scenario | Steps to Reproduce | Expected Result | Pass/Fail |
|---|---|---|---|---|
| PREV-01 | Image Preview & Zoom | Tap encrypted JPEG/PNG file. | Image decodes smoothly; pinch-to-zoom and pan functional. | Pending |
| PREV-02 | Video Streaming & Seeking | Tap encrypted 1 GB MP4 video. | Video begins playing within 1-2 seconds via local streaming proxy; scrubbing forward fetches targeted byte range. | Pending |
| PREV-03 | Audio Playback | Tap encrypted MP3/FLAC file. | Audio player appears with waveform/controls; plays continuously. | Pending |
| PREV-04 | PDF Viewer | Tap encrypted PDF document. | PDF renders with page navigation and smooth zoom. | Pending |
| PREV-05 | Code & Text Viewer | Tap `.dart`, `.json`, `.txt` file. | Syntax-highlighted text reader displays formatted code. | Pending |
| PREV-06 | Share Decrypted Copy | Open file > Tap Share icon > Open in third-party app. | File decrypted to temporary sandbox file; shared via OS sheet; temp file cleaned up after sharing. | Pending |

---

## 5. Cross-Device Cloud Sync & Recovery

| Test ID | Scenario | Steps to Reproduce | Expected Result | Pass/Fail |
|---|---|---|---|---|
| SYNC-01 | Index Snapshot Backup | Perform uploads and folder reorganization. | Pinned index message in "Filo Vault" channel automatically updated with latest encrypted snapshot. | Pending |
| SYNC-02 | Disaster Recovery on New Device | Install app on fresh device. Login with same Telegram account. Enter passphrase. | App locates pinned index; decrypts snapshot; full folder tree and file list restored with 100% integrity. | Pending |
| SYNC-03 | Incorrect Passphrase on Restore | Enter wrong passphrase during restore. | Argon2id verification fails; clear notification that passphrase does not match without decrypting corrupted data. | Pending |
| SYNC-04 | GDPR "Export Everything" | Go to Settings > Export All Data. | App decrypts all files in background stream and packages into a single `.zip` file. | Pending |
| SYNC-05 | GDPR "Delete All My Data" | Go to Settings > Delete All Remote & Local Data. | All messages in Telegram vault channel deleted; local database wiped. | Pending |
