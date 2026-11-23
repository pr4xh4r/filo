# App Store & Google Play Store Submission Guide (STORE.md)

## 1. App Store Metadata

- **App Name**: Filo - Private Cloud Vault
- **Subtitle**: Zero-Knowledge Cloud Powered by Your Telegram
- **Primary Category**: Productivity
- **Secondary Category**: Utilities
- **Keywords**: cloud storage, secure vault, zero knowledge, encrypted drive, file manager, telegram cloud, private drive, privacy, photo backup, encrypted storage
- **Content Rating**: 4+ (No mature or objectionable content)

### Promotional Text
Turn your own Telegram into a private, zero-knowledge encrypted cloud drive. No servers, no tracking, complete ownership.

### Full Description
Filo is a personal cloud storage and file manager app that uses your OWN Telegram account as a secure, decentralized storage backend. 

With Filo, your files live exclusively in your own private Telegram channel, secured with military-grade client-side encryption. We run no servers, maintain no databases, and store zero user data. You maintain 100% ownership and control over your digital life.

WHY FILO?
• ZERO-KNOWLEDGE ENCRYPTION: Every file is encrypted on your device with AES-256-GCM before it ever leaves your phone. Encryption keys are derived from your personal passphrase using Argon2id. Even Telegram cannot see what you store.
• UNLIMITED PERSONAL CLOUD: Leverage Telegram’s cloud infrastructure to store documents, high-resolution photos, 4K videos, and archives.
• BEAUTIFUL VIRTUAL FOLDERS: Organize your files into nested virtual folders, color tags, and favorites—all synced through an encrypted index.
• INSTANT PREVIEWS: Stream encrypted videos without waiting for full downloads. Preview photos, audio tracks, PDFs, and source code directly in the app.
• RESUMABLE LARGE FILE TRANSFERS: Automatic chunking splits files of any size with auto-resume across network drops or app restarts.
• DISASTER RECOVERY & SYNC: Log in on a new device, enter your passphrase, and your entire virtual cloud is restored automatically.
• OPEN AND AUDITABLE: Zero developer servers. Transparent, verifiable cryptography.

DISCLAIMER & INDEPENDENCE:
Filo is an independent client application built using Telegram's open MTProto and Bot APIs. Filo is NOT affiliated with, sponsored by, or endorsed by Telegram FZ-LLC. All product and company names are trademarks™ or registered® trademarks of their respective holders.

---

## 2. Google Play Data Safety Answers

| Section | Question | Answer | Rationale |
|---|---|---|---|
| **Data Collection** | Does your app collect or share any user data? | **No** | Filo does NOT collect any user data to developer servers or third-party analytics. |
| **Data in Transit** | Is all data encrypted in transit? | **Yes** | All data transmitted to Telegram is encrypted client-side with AES-256-GCM and transport-encrypted via MTProto / TLS. |
| **Data Deletion** | Can users request data deletion? | **Yes** | Built-in "Delete All My Data" feature permanently purges all remote messages in the vault channel and wipes local databases. |
| **Account Info** | Is phone number or user info collected? | **No** | Telegram phone authentication is handled directly by TDLib on-device communicating with Telegram servers. No credentials are transmitted to any other party. |

---

## 3. Apple Privacy Nutrition Label

- **Data Used to Track You**: None (0)
- **Data Linked to You**: None (0)
- **Data Not Linked to You**: None (0)
- **App Privacy Verdict**: "Data Not Collected". The developer does not collect any data from this app.

---

## 4. Screenshot & Visual Plan

1. **Screen 1**: *Your Telegram is now your private cloud.* Hero illustration with clean file grid and end-to-end encryption badge.
2. **Screen 2**: *Zero-Knowledge by default.* Showing AES-256-GCM client-side encryption, Argon2id passphrase setup.
3. **Screen 3**: *Fast, organized file management.* Virtual folders, search, tag filters, batch operations.
4. **Screen 4**: *Instant media previews & streaming.* Video player streaming encrypted 4K footage without downloading.
5. **Screen 5**: *Cross-device restore.* Show restoring entire cloud drive on a new device with passphrase.
