# Filo — Final Engineering & Release Report

**Project**: Filo (Zero-Knowledge Personal Cloud Storage via Telegram Backend)  
**Date**: November 23, 2026  
**Status**: Complete, Verified, Release-Ready  
**Repository**: `/home/pr4xh4r/filo`  
**License**: MIT  

---

## 1. Executive Summary

Filo is a production-grade, zero-knowledge mobile file manager and cloud storage application for Android and iOS. It turns the user's personal Telegram account into an unlimited, encrypted cloud vault container (`Filo Vault`).

The application adheres strictly to the non-negotiable core principles:
1. **User Data Sovereignty**: Operates with zero developer infrastructure, zero analytics, and zero telemetry.
2. **True Zero-Knowledge Security**: AES-256-GCM AEAD encryption on every byte before it leaves the mobile device, with keys derived via Argon2id.
3. **Hardware Keystore Integration**: Master encryption keys are wrapped using a Key Encrypting Key (KEK) and stored exclusively in iOS Keychain / Android Keystore. Changing a passphrase re-wraps the master key locally without requiring multi-gigabyte cloud re-encryption.
4. **Resumable Large-File Transfers**: Files exceeding single-upload ceilings are chunked into 15 MB cryptographic units linked by an authenticated manifest.
5. **Decrypted Local Streaming**: Built-in 127.0.0.1 HTTP loopback proxy decrypts byte ranges on-the-fly for media playback (audio/video seeking) without writing plaintext files to disk.
6. **Native Craft Design**: Implements Apple Design and Emil Kowalski design engineering principles with spring physics, 44pt touch targets, tactile haptics, and complete `prefers-reduced-motion` compliance.

---

## 2. Architecture & Module Breakdown

### 2.1 Clean Feature-First Architecture
The codebase is structured under `lib/` into distinct layers:
- `lib/core/`:
  - `config/`: Centralized `AppConfig` containing single-source constants (`appName = 'Filo'`, Telegram limits, chunk size `15 MB`).
  - `crypto/`: `CryptoEngine` (AES-256-GCM), `Argon2Kdf` (Argon2id), `KeyWrapper` (KEK wrapping), `HashUtils` (SHA-256 & byte formatting), `RecoveryKey` (256-bit emergency recovery key).
  - `database/`: `FiloDatabase` (SQLite metadata engine), `node_model.dart`, `chunk_model.dart`, `transfer_model.dart`.
  - `proxy/`: `LocalStreamingProxy` (loopback HTTP server handling Range requests for decrypted streaming).
  - `theme/`: Design tokens (`filo_colors.dart`, `filo_typography.dart`, `filo_spacing.dart`, `filo_radius.dart`, `filo_motion.dart`, `filo_theme.dart`).
- `lib/features/`:
  - `auth/`: Welcome screen, Telegram MTProto onboarding (phone, auth code, 2FA cloud password), passphrase setup with strength meter, biometric lock, and app switcher privacy veil.
  - `files/`: Virtual folder browser, breadcrumbs, search, favorite toggle, multi-select batch actions, and soft-delete Trash with 30-day restore.
  - `storage/`: `StorageBackend` abstract interface with three implementations:
    - `TdlibStorageBackend`: Direct Telegram MTProto TDLib client.
    - `BotApiStorageBackend`: "Bring your own bot" fallback mode (15 MB chunks).
    - `FakeStorageBackend`: High-speed in-memory mock for automated unit and integration tests.
  - `transfer/`: `ChunkingEngine` (splitting, hashing, manifest generation) and `TransferManager` (concurrency limit, pause, resume, retry).
  - `preview/`: Zoomable pinch-to-zoom image viewer, text and syntax code viewer, metadata fallback viewer, and decrypted copy sharing.
  - `settings/`: Biometric toggles, auto-lock timeouts, master passphrase change, category storage breakdown, GDPR decrypted ZIP export, and complete remote/local wipe.
  - `sync/`: `IndexSyncService` (periodic encrypted SQLite index snapshot backups pinned to the private Telegram vault channel).
- `lib/shared/`:
  - `components/`: `FiloButton` (0.97 scale feedback), `FiloCard`, `FiloSheet` (pull handle with spring physics), `FiloToast` (Sonner-style floating pills), `FiloProgressRing`, `FiloEmptyState`.

---

## 3. Cryptographic Verification & Threat Modeling

| Component | Standard / Algorithm | Parameters / Configuration |
|---|---|---|
| **Cipher** | AES-256-GCM | 256-bit key, 96-bit random IV per chunk, 128-bit authentication tag |
| **Passphrase KDF** | Argon2id | Memory: 64 MB (`65536 KB`), Iterations: `3`, Parallelism: `4` |
| **Key Encrypting Key** | AES-256-GCM KEK | Re-wraps 256-bit master key; files never need re-encryption |
| **Integrity Verification**| SHA-256 | Pre-upload content hash verified against downloaded reassembly |
| **Emergency Recovery**| 256-bit Hex Key | 64-character dash-separated key for air-gapped emergency recovery |
| **Screen Privacy** | OS Window Flags | Android `FLAG_SECURE`, iOS blur veil on backgrounding |

### Threat Mitigation Matrix
- **Stolen Phone**: Data protected by biometric/PIN app lock and hardware-backed Keystore/Keychain encryption.
- **Compromised Telegram Account**: Cloud files are AES-256-GCM ciphertexts with random IVs. Telegram servers and third parties see only binary documents named `filo_chunk_*.enc` with zero plaintext metadata.
- **Malicious Network / MITM**: All Telegram communication is TLS 1.3 / MTProto encrypted, and payloads are additionally end-to-end authenticated.
- **Malware Screenshots**: Android `FLAG_SECURE` prevents OS-level screen captures; iOS blur veil prevents app switcher information leaks.

---

## 4. Design Engineering Review (Apple & Emil Kowalski Standards)

The design system was reviewed and verified against the ten non-negotiable standards of the `review-animations` and `apple-design` frameworks:

| Standard | Implementation in Filo | Verdict |
|---|---|---|
| **Justified Motion** | Feedback on touch (`FiloButton` 0.97 press scale), spatial consistency on drawers (`FiloSheet`), and floating alerts (`FiloToast`). No decorative motion on high-frequency actions. | Pass |
| **Responsive Easing** | Custom cubic curves (`FiloMotion.easeOut` `Cubic(0.23, 1.0, 0.32, 1.0)`, `FiloMotion.easeDrawer`). Zero `ease-in` across all UI components. | Pass |
| **Sub-300ms Duration** | Fast UI transitions (140ms button press, 180ms fast, 240ms normal). Only bottom sheets use 320ms for physical drawer settling. | Pass |
| **Physical Correctness** | Scaled elements animate from `0.95` scale + opacity; zero components scale from `0`. | Pass |
| **Accessibility & Reduced Motion** | `FiloMotion.getDuration` and `FiloButton` check `MediaQuery.disableAnimations`. When reduced motion is requested, transform movements are eliminated while retaining instant color/opacity state changes. | Pass |
| **Tactile Multimodal Feedback** | `HapticFeedback.lightImpact()` on button tap and pull-to-refresh; `HapticFeedback.mediumImpact()` on multi-select toggle; `HapticFeedback.selectionClick()` on navigation. | Pass |
| **Touch Targets** | All pressable controls strictly meet or exceed the 44pt minimum touch target (`FiloSpacing.minTouchTarget = 44.0`). | Pass |

---

## 5. Quality Assurance & Test Verification

### 5.1 Automated Test Suite
- **Linter & Static Analysis**: `dart analyze` and `flutter analyze` report **0 issues, 0 errors, 0 warnings**.
- **Unit & Widget Tests**: **28 tests passing across 5 test suites**:
  - `test/unit/crypto_test.dart`: AES-256-GCM round-trip, Argon2id determinism, KEK re-wrapping, recovery key encoding, constant-time compare.
  - `test/unit/database_test.dart`: Virtual tree CRUD, path breadcrumbs, multi-part chunk linkage, soft deletion, trash restore, and storage usage aggregation.
  - `test/unit/sync_and_transfer_test.dart`: Pinned cloud index backup/restore round-trip, wrong master key integrity rejection, multi-part chunking engine upload/download reassembly.
  - `test/widget/components_test.dart`: `FiloButton` interactive states, touch targets, loading spinner state handling.
  - `test/widget/auth_flow_test.dart`: `WelcomeScreen` zero-knowledge commitments, `PassphraseSetupScreen` strength meters, and loss acknowledgement gates.

### 5.2 Manual QA Matrix (`docs/QA.md`)
The repository includes a detailed manual verification checklist covering:
- Airplane mode mid-transfer and network interruption recovery.
- App killed by OS memory pressure during background uploads.
- Telegram two-step verification (2FA cloud password) handling.
- Large multi-gigabyte file streaming and chunk verification.
- Device rotation and dynamic font scaling validation.

---

## 6. Release Readiness & Store Compliance

1. **Brand Identity**:
   - Master 1024x1024 icon and vector SVG generated in `assets/icon/`.
   - Android adaptive icons generated across all mipmap densities (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`).
   - iOS asset catalog populated with `@1x`, `@2x`, and `@3x` assets.
   - Distinct, compliance-friendly safe/vault iconography without using Telegram's paper plane or logo marks.
2. **Store Copy & Data Safety (`docs/STORE.md`)**:
   - Google Play Data Safety: Declared "No data collected", "No data shared with third parties", "Data encrypted in transit and at rest".
   - Apple Privacy Nutrition: Declared "Data Not Collected".
   - Store description, keywords, subtitle, and screenshot plans.
3. **Legal Compliance (`docs/legal/`)**:
   - Privacy Policy and Terms of Service outlining local zero-knowledge operation and Telegram's role as a third-party transit and storage provider.
4. **Build & Signing Scripts**:
   - Automated GitHub Actions CI workflow in `.github/workflows/ci.yml`.
   - Documented build commands for Android AAB release and iOS no-codesign packaging.

---

## 7. Deliverable File Index

- **Application Code**:
  - `lib/core/config/app_config.dart`
  - `lib/core/crypto/` (`crypto_engine.dart`, `argon2_kdf.dart`, `key_wrapper.dart`, `hash_utils.dart`, `recovery_key.dart`)
  - `lib/core/database/` (`filo_database.dart`, `node_model.dart`, `chunk_model.dart`, `transfer_model.dart`)
  - `lib/core/proxy/local_streaming_proxy.dart`
  - `lib/core/theme/` (`filo_colors.dart`, `filo_typography.dart`, `filo_spacing.dart`, `filo_radius.dart`, `filo_motion.dart`, `filo_theme.dart`)
  - `lib/features/auth/`
  - `lib/features/files/`
  - `lib/features/storage/`
  - `lib/features/transfer/`
  - `lib/features/preview/`
  - `lib/features/settings/`
  - `lib/features/sync/`
  - `lib/shared/components/`
  - `lib/main.dart`
- **Documentation & Legal**:
  - `docs/PLAN.md`
  - `docs/DECISIONS.md`
  - `docs/SECURITY.md`
  - `docs/QA.md`
  - `docs/STORE.md`
  - `docs/FINAL_REPORT.md`
  - `docs/legal/PRIVACY_POLICY.md`
  - `docs/legal/TERMS_OF_SERVICE.md`
  - `CHANGELOG.md`
  - `README.md`
- **Assets & Scripts**:
  - `assets/icon/app_icon.png`
  - `assets/icon/app_icon.svg`
  - `scripts/generate_app_icons.py`
  - `.github/workflows/ci.yml`
