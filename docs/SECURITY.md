# Threat Model & Cryptographic Security Architecture (SECURITY.md)

## 1. Core Security Tenets
1. **Zero-Knowledge by Default**: Filo operates on the mathematical principle that no party—neither Filo developers, Telegram employees, nor network eavesdroppers—can read user data, file names, folder structures, or metadata without the user's secret passphrase.
2. **No Developer Infrastructure**: The app possesses no central servers, no telemetry touching content, no third-party analytics trackers, and no developer-held keys.
3. **Defense in Depth**: Security controls operate across multiple layers: hardware keystores, client-side cryptographic primitives, authenticated database encryption, memory scrubbing, and OS sandboxing.

---

## 2. Threat Model Analysis

### 2.1 Threat Vector: Stolen or Lost Physical Device
- **Threat Actor**: Opportunistic thief or targeted attacker possessing the physical phone.
- **Attack Vectors**:
  - Extracting unencrypted SQLite databases or shared preferences.
  - Sifting through thumbnail caches or temporary folders.
  - Bypassing the app if unlocked.
- **Mitigations**:
  - **Encrypted Database**: Drift/SQLite is encrypted using SQLCipher with a 256-bit AES key.
  - **Hardware Keystore Protection**: Wrapped Master Key and DB keys are stored in iOS Keychain / Android Keystore, gated behind biometric auth (FaceID / Fingerprint) or system device passcode.
  - **Auto-Lock Timer**: App locks immediately on backgrounding or after a user-configured timeout (e.g. 1 min, 5 min).
  - **Zero Unencrypted Temp Files**: Decrypted temporary files (created when sharing a file via the OS share sheet) are created with restricted permissions in private app cache directories and immediately scrubbed on share sheet dismissal or app exit.
  - **Encrypted Thumbnails**: Thumbnail cache is stored encrypted in private sandbox directory and governed by an LRU eviction policy.

### 2.2 Threat Vector: Compromised Telegram Session / Account Takeover
- **Threat Actor**: Attacker who gains access to the user's Telegram session (e.g. SIM swap, unauthorized desktop Telegram login).
- **Attack Vectors**:
  - Reading messages in the user's private "Filo Vault" channel.
  - Downloading stored files from Telegram messages.
  - Tampering with or deleting files.
- **Mitigations**:
  - **Zero Plaintext in Telegram**: Telegram messages in "Filo Vault" contain exclusively encrypted binary blobs (AES-256-GCM ciphertext) with randomized file names (e.g. UUIDs like `0a3f81c9-4b2e...part0.enc`).
  - **Original File Names & Folder Hierarchy are Encrypted**: Metadata lives entirely inside the encrypted index snapshot; Telegram servers only observe opaque binary chunks.
  - **Authenticated Encryption (AEAD)**: Every chunk is protected by AES-256-GCM with a 128-bit authentication tag. Any attempt by an attacker to alter ciphertext bytes causes MAC validation failure, discarding the corrupted chunk before decryption.
  - **Integrity Hashes**: SHA-256 hashes of every ciphertext chunk are recorded in the manifest and verified before decryption.

### 2.3 Threat Vector: Rogue Telegram Administrator or Insider
- **Threat Actor**: Telegram engineer or government subpoena compelling Telegram to hand over channel data.
- **Attack Vectors**:
  - Inspecting message history, files, and attachments in the user's private channel.
- **Mitigations**:
  - Without the user's passphrase (derived via memory-hard Argon2id), brute-forcing the AES-256-GCM keys from ciphertext is computationally infeasible according to modern cryptographic standards.

### 2.4 Threat Vector: Man-in-the-Middle (MitM) & Network Eavesdropping
- **Threat Actor**: Malicious Wi-Fi access point, ISP, or rogue TLS proxy.
- **Attack Vectors**:
  - Intercepting network traffic between the device and Telegram servers.
- **Mitigations**:
  - **MTProto Protocol Security**: TDLib natively uses Telegram's MTProto 2.0 protocol with Diffie-Hellman key exchange and end-to-end transport encryption.
  - **Pre-Transport Encryption**: Files are encrypted with AES-256-GCM on-device *before* passing to the network layer. Even if TLS or MTProto were theoretically compromised, the attacker only obtains ciphertext.

### 2.5 Threat Vector: Malware, Screen Recording & Shoulder Surfing
- **Threat Actor**: Malicious screen recorder app, OS screenshot previews in task switchers.
- **Attack Vectors**:
  - Background snapshot taken by iOS/Android when task switching.
  - Malicious background app capturing screen.
- **Mitigations**:
  - **Android `FLAG_SECURE`**: Enabled when app lock is active to prevent screenshots and screen capture.
  - **iOS Privacy Blur Screen**: On `AppLifecycleState.inactive` and `paused`, Filo immediately displays a solid privacy shield/blur overlay, ensuring the OS switcher snapshot captures no sensitive data.

---

## 3. Cryptographic Implementation Details

### 3.1 Primitives & Parameters
- **Symmetric Cipher**: AES-256 in Galois/Counter Mode (GCM).
  - Key size: 256 bits (32 bytes).
  - Initialization Vector (IV): 96 bits (12 bytes), generated freshly for every chunk using CSPRNG (`Random.secure()`).
  - Tag length: 128 bits (16 bytes).
- **Key Derivation Function (KDF)**: Argon2id.
  - Memory cost: 64 MB (65,536 KiB).
  - Iterations (Time cost): 3.
  - Parallelism: 4 threads.
  - Salt: 16 bytes cryptographically secure random bytes.
- **Master Key Generation**: 256 bits of CSPRNG entropy generated on initial vault creation.
- **Master Key Wrapping**:
  - `WrappedMasterKey = AES-GCM(KEK, MasterKey, IV_wrap, Tag)`
  - When the user changes their passphrase, only the KEK is regenerated and the MasterKey re-wrapped. No files in Telegram require re-encryption.

### 3.2 Secure Memory & Logging Guardrails
- **Zero Sensitive Logging**: Strict rule enforced across all code: file names, paths, passphrases, tokens, chunk hashes, and keys are NEVER logged to console or crash reporting.
- **Zero Unpinned Dependencies**: All third-party packages are pinned to exact versions and reviewed for supply chain vulnerabilities.
- **Jailbreak / Root Detection**: Checked on startup; if detected, a non-blocking security advisory warns the user about compromised sandbox isolation.
