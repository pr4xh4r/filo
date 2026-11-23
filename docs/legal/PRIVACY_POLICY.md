# Privacy Policy for Filo

*Last Updated: November 23, 2026*

## 1. Introduction & Core Principle
Filo ("we", "our", or "the App") is committed to absolute user privacy. Our foundational architecture is **zero-knowledge and decentralized**. 
- **We do not operate servers.**
- **We do not store user data.**
- **We do not collect personal analytics, telemetry, or device identifiers.**
- **We do not hold or manage your encryption keys.**

Everything you store using Filo remains exclusively on your personal device and in your own private Telegram channel.

---

## 2. Information We Do NOT Collect
- We do **not** collect or store your name, email address, or phone number.
- We do **not** collect your file names, folder names, file contents, or MIME types.
- We do **not** collect IP addresses, hardware identifiers, advertising IDs, or location data.
- We do **not** track your usage, clicks, browsing behavior, or storage volume.

---

## 3. How Authentication and Storage Work

### 3.1 Telegram Authentication
When you authenticate within Filo, the connection is established directly between your device and Telegram's official servers using Telegram's MTProto protocol (TDLib) or the official Telegram Bot API. 
Your phone number, verification codes, and two-factor authentication (2FA) passwords are transmitted directly to Telegram and are never accessible, recorded, or intercepted by the creators of Filo.

### 3.2 On-Device Encryption
Before any file or metadata is uploaded to your Telegram account:
1. It is encrypted directly on your device using industry-standard **AES-256-GCM**.
2. The encryption key is derived on-device from your secret passphrase using **Argon2id**.
3. Telegram only receives scrambled, authenticated ciphertext. Telegram cannot view the contents or names of your files.
4. Your master key and derived credentials are saved exclusively in your device's hardware-backed secure storage (iOS Keychain / Android Keystore).

---

## 4. Third-Party Services
Filo connects exclusively to:
- **Telegram (Telegram FZ-LLC)**: Used solely as a user-directed storage repository. Your relationship with Telegram is governed by Telegram's own Privacy Policy and Terms of Service.

Filo does not embed third-party analytics SDKs, advertising trackers, or telemetry brokers.

---

## 5. Data Deletion and Portability (GDPR & CCPA Compliance)
You retain total control over your data:
- **Export All Data**: The app provides a direct "Export Everything" tool to decrypt and package all your stored files into a standard archive.
- **Delete All Data**: The app provides a "Delete All My Data" feature that permanently erases all remote encrypted blobs in your Telegram vault channel and wipes all local databases.

---

## 6. Children's Privacy
Filo does not knowingly collect or solicit data from children under the age of 13.

---

## 7. Contact
For questions regarding this Privacy Policy or the open source architecture of Filo, please visit our official GitHub repository.
