# Changelog

All notable changes to **Filo** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-23

### Added
- **Core Architecture & Philosophy**:
  - Zero-knowledge on-device encryption pipeline using authenticated AES-256-GCM AEAD.
  - Argon2id Key Derivation Function (KDF) parameterized with 64 MB memory, 3 iterations, and 4 threads.
  - Master Key wrapping & re-wrapping via Key Encrypted Key (KEK) allowing instant passphrase changes without re-encrypting stored files.
  - 256-bit emergency recovery key generation, formatting, and offline parsing.
  - Local encrypted SQLite metadata database with SQLCipher-grade design storing virtual folder hierarchy, file metadata, trash management, and full-text search.
- **Telegram Cloud Storage Backend**:
  - Abstract swappable `StorageBackend` interface.
  - MTProto TDLib backend supporting user login (phone, auth code, 2FA cloud password) and dedicated private channel container `"[APP_NAME] Vault"`.
  - Bot API fallback backend with automatic 15 MB chunking staying strictly under Telegram Bot API 20 MB limits.
  - High-performance offline `FakeStorageBackend` for tests and air-gapped verification.
  - Resumable chunked file streaming with multi-part manifest support for files exceeding single-file platform limits (> 1.5 GB).
  - Loopback 127.0.0.1 decrypted HTTP streaming proxy for direct video/audio seekable playback.
- **File Management & Organization**:
  - Virtual folder tree: create, rename, move, delete, and restore folders and files.
  - Soft-delete Trash bin with 30-day retention and restore capability.
  - Star / favorite files for instant quick access.
  - Multi-select batch mode with bulk deletion.
  - In-memory duplicate content detection using SHA-256 fingerprinting.
  - Full-text search by name, mime type, and folder scope.
  - Grid view and List view toggling with persistent user preference.
- **Reliability & Cloud Synchronization**:
  - Encrypted cloud index backup: periodic snapshots exported and pinned to the private vault channel.
  - Cross-device restore flow: new device logs in, provides passphrase, verifies authenticated snapshot, and reconstructs full local SQLite index.
  - Network loss recovery, pause, resume, and concurrency limiter (max 3 concurrent transfers).
  - Rate limit backoff mechanism handling Telegram `FLOOD_WAIT_X` events gracefully.
- **Design System & UX**:
  - Built on Emil Kowalski and Apple design guidelines (`apple-design`, `emil-design-eng`, `review-animations`).
  - Spring-based physics, 44pt touch targets, tactile haptics (`HapticFeedback.lightImpact`, `mediumImpact`, `selectionClick`).
  - Strict compliance with `prefers-reduced-motion` eliminating vestibular motion while retaining status transitions.
  - Sonner-style floating toast notification system (`FiloToast`).
  - Interactive media previews (zoomable pinch-to-zoom image viewer, text/syntax code viewer, metadata fallback).
  - App switcher privacy shield (Android `FLAG_SECURE`, iOS blur veil).
  - Storage breakdown analytics visualizing disk usage across Photos, Videos, Audio, Documents, and Others.
  - GDPR-compliant data export ("Export Everything" as decrypted ZIP) and "Delete All My Data" remote/local wipe.
- **Release Assets & Documentation**:
  - Comprehensive architectural plan (`docs/PLAN.md`).
  - Architectural Decisions Log (`docs/DECISIONS.md`).
  - Full threat model and cryptanalysis (`docs/SECURITY.md`).
  - End-to-end QA verification matrix (`docs/QA.md`).
  - Store listings, Google Play Data Safety, Apple Privacy Nutrition details (`docs/STORE.md`).
  - Legal zero-knowledge privacy policy and Telegram disclaimer (`docs/legal/`).
  - Master icons for Android adaptive launcher and iOS asset catalog.
