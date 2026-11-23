# Architectural Decisions (DECISIONS.md)

This document records all architectural, technical, and design decisions made for **Filo**, their context, rationale, and consequences.

---

### DECISION-0001: Application Name and Branding Customization
- **Date**: 2026-11-23
- **Context**: The app specification defines `Filo` as the application name, but requires it to be configurable via a single constant so the app can be rebranded easily.
- **Decision**: Define `AppConfig.appName` and related constants in `lib/core/config/app_config.dart`. All user-facing strings, storage channel naming (`"${AppConfig.appName} Vault"`), default export file names, and notification channels reference this constant.
- **Consequences**: Easy rebranding with zero hardcoded "Filo" strings scattered in the codebase.

---

### DECISION-0002: Storage Backend Abstraction (`StorageBackend`)
- **Date**: 2026-11-23
- **Context**: Primary storage backend uses Telegram MTProto (TDLib via FFI), but Telegram Bot API ("Bring Your Own Bot") must be supported as a swappable fallback.
- **Decision**:
  1. Define a unified abstract interface `StorageBackend`:
     - `Future<void> initialize(...)`
     - `Future<AuthSessionState> checkAuth()`
     - `Future<ChannelMetadata> getOrCreateVaultChannel(String channelTitle)`
     - `Stream<UploadProgress> uploadPart({required String channelId, required Stream<List<int>> dataStream, required String partFileName, required int partSize})`
     - `Stream<List<int>> downloadPart({required String channelId, required String remoteFileId, required int offset, required int limit})`
     - `Future<void> deleteMessage({required String channelId, required String messageId})`
     - `Future<RemoteMessageId> pinMessage({required String channelId, required String messageId})`
     - `Future<RemoteMessage?> getPinnedMessage({required String channelId})`
  2. Implement `TdlibStorageBackend` using `flutter_tdlib` / native TDLib FFI bindings for full MTProto client accounts (supports files up to 2GB standard / 4GB Premium).
  3. Implement `BotApiStorageBackend` using Telegram Bot HTTP API (supports bot token + user chat ID, with 19MB maximum chunk size to strictly obey Bot API `getFile` 20MB download limit).
  4. Implement `FakeStorageBackend` for end-to-end unit and integration testing without requiring live Telegram network connections or SMS codes.
- **Consequences**: Decoupled architecture, fully testable without network, interchangeable backends.

---

### DECISION-0003: Cryptographic Architecture & Key Management
- **Date**: 2026-11-23
- **Context**: Zero-knowledge encryption requirement. Files must be encrypted on-device before uploading to Telegram. If Telegram or any intermediary intercepts messages, they only see random ciphertext.
- **Decision**:
  1. **Master Key**: Generated on device using `Random.secure()` (256-bit cryptographically secure entropy).
  2. **Key Derivation (Passphrase)**: Use `Argon2id` (memory cost: 64MB, iterations: 3, parallelism: 4, 16-byte random salt) to derive a Key Encryption Key (KEK).
  3. **Master Key Wrapping**: Master Key is encrypted with the KEK using AES-256-GCM and stored in device secure storage (`flutter_secure_storage`: iOS Keychain / Android Keystore with Biometric protection).
  4. **Passphrase Change**: Changing passphrase only requires decrypting the Master Key with the old KEK, generating a new salt, deriving a new KEK, and re-encrypting (re-wrapping) the Master Key. Existing encrypted files in Telegram do **not** need re-encryption.
  5. **File Encryption**: AES-256-GCM with unique 96-bit IV per chunk. File content is split into deterministic chunks (e.g. 15MB for Bot API, 32MB for MTProto). Each chunk has its own authentication tag (128-bit) and SHA-256 integrity hash.
  6. **Recovery Key**: 128-bit or 256-bit entropy represented as BIP39-style mnemonic phrase or formatted hexadecimal backup string that can unwrap the Master Key in emergencies.
- **Consequences**: Mathematically proven zero-knowledge security. Fast passphrase changes without touching stored cloud data.

---

### DECISION-0004: Encrypted Local Database & Index Backup
- **Date**: 2026-11-23
- **Context**: The app needs an instant, offline-first local file index that can scale to 10,000+ files with sub-millisecond queries, full-text search, and relational integrity.
- **Decision**:
  1. **Engine**: Drift with SQLCipher (`sqlcipher_flutter_libs` / `sqlite3_flutter_libs`), encrypted with a 256-bit database key stored in Secure Storage.
  2. **Tables**:
     - `nodes`: Represents folders and files (id, parent_id, name, type, size_bytes, mime_type, content_hash, created_at, modified_at, is_favorite, is_trashed, trashed_at, encryption_iv, manifest_json, sync_status).
     - `chunks`: Detailed chunk mapping for multi-part files (node_id, chunk_index, remote_message_id, remote_file_id, size_bytes, sha256_hash, iv).
     - `sync_metadata`: Local and remote vector clocks, last index snapshot timestamp, pinned message ID.
     - `transfer_tasks`: Persistent queue of uploads/downloads with resume states.
  3. **Cloud Snapshot (Index Sync)**: The entire index metadata is serialized to a compact JSON/Protocol buffer structure, encrypted using the Master Key, and sent as a document message to the Telegram Vault channel, pinned at the top. On login from a new device, the app fetches the pinned message, decrypts the index with the user's passphrase, and rebuilds the local database.
- **Consequences**: Single source of truth locally, instant UI response, robust disaster recovery across devices.

---

### DECISION-0005: Resumable Chunked Streaming & Local Decrypting Media Proxy
- **Date**: 2026-11-23
- **Context**: Handling multi-gigabyte video and media files without running out of memory, while supporting random seek in video player.
- **Decision**:
  1. **Streaming Transfers**: Never read an entire file into RAM. Files are streamed directly from disk through AES-GCM Cipher sinks into HTTP/MTProto upload multipart streams.
  2. **Streaming Video/Audio Playback**: Implement a lightweight local `HttpServer` bound strictly to `127.0.0.1` on an ephemeral port. When the user taps a video, the media player requests `http://127.0.0.1:<port>/stream/<nodeId>`. The proxy server translates HTTP Range requests (`bytes=start-end`) to specific encrypted chunk downloads, decrypts only the requested byte ranges on the fly, and streams plaintext directly into the player buffer.
- **Consequences**: Zero memory pressure, instant playback start, smooth seeking in large videos without downloading the entire file first.

---

### DECISION-0006: Design System & Animation Philosophy
- **Date**: 2026-11-23
- **Context**: App must strictly implement the Emil Kowalski & Apple design engineering principles: spring physics, interruptible animations, 44pt touch targets, design tokens, and restrained color palette.
- **Decision**:
  1. Build a centralized design token system in `lib/core/theme/`: `FiloColors`, `FiloTypography`, `FiloSpacing`, `FiloRadius`, `FiloShadows`, `FiloMotion`.
  2. Motion curves:
     - Default entrance: `Curves.easeOutCubic` (response: 200–250ms).
     - Modals/sheets: Spring simulations or custom cubic `Cubic(0.32, 0.72, 0.0, 1.0)`.
     - Button press: instant scale feedback (`scale: 0.97`) on tap down, returning on tap up.
     - Never animate keyboard shortcuts or 100+/day core list navigations.
     - Honoring `prefers-reduced-motion` via `MediaQuery.disableAnimationsOf(context)` with subtle opacity fades instead of translation.
  3. Minimum touch target of 44x44pt on all interactive elements.
- **Consequences**: Premium native iOS/Android feel, fluid interactions, accessibility compliant.

---

### DECISION-0007: App Switcher Blur & Sensitive Screen Protection
- **Date**: 2026-11-23
- **Context**: Stored file previews and file names must never leak via OS app switcher screenshots or screen recording.
- **Decision**:
  1. Use Android `FLAG_SECURE` when biometric/security lock is enabled.
  2. Overlay a privacy protection screen / blur layer in Flutter when the app lifecycle transitions to `AppLifecycleState.inactive` or `AppLifecycleState.paused`.
- **Consequences**: Zero accidental leakage in task switchers or screen recorders.
