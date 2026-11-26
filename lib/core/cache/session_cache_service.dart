import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages temporary, zero-knowledge session caching for decrypted media
/// (videos, photos, PDFs, and documents).
///
/// Principles:
/// 1. Low RAM Consumption: Decrypted media streams directly to disk-backed files
///    rather than keeping giant byte arrays in the Dart heap.
/// 2. Instant Navigation: Decrypted files remain cached within the active unlocked session,
///    so moving across folders and reopening files is 0ms instant without re-downloading.
/// 3. Zero-Knowledge Hygiene: When the vault locks or the app lifecycle pauses/terminates,
///    [purge] completely scrubs the session cache from device storage.
/// 4. LRU Space Guard: Automatically evicts oldest cached files if the session cache
///    exceeds 250 MB or 20 files, keeping internal storage minimal.
class SessionCacheService {
  SessionCacheService._();
  static final SessionCacheService instance = SessionCacheService._();

  static const String sessionDirName = 'filo_session';
  static const int maxCacheSizeBytes = 250 * 1024 * 1024; // 250 MB
  static const int maxCacheFiles = 20;

  Directory? _cachedSessionDir;

  @visibleForTesting
  void setOverrideDirectory(Directory? dir) {
    _cachedSessionDir = dir;
  }

  /// Retrieves or creates the isolated session cache directory.
  Future<Directory> getSessionDirectory() async {
    if (_cachedSessionDir != null && await _cachedSessionDir!.exists()) {
      return _cachedSessionDir!;
    }
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, sessionDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedSessionDir = dir;
    return dir;
  }

  /// Returns a valid cached session file if one already exists for [nodeId].
  /// Validates [expectedSize] if provided to guarantee data integrity.
  Future<File?> getCachedFile(String nodeId, {int? expectedSize}) async {
    try {
      final dir = await getSessionDirectory();
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final base = p.basename(entity.path);
          if (base.startsWith('session_$nodeId.') || base == 'session_$nodeId') {
            if (expectedSize != null && expectedSize > 0) {
              if (entity.lengthSync() != expectedSize) {
                // Incomplete or corrupted stream, remove it
                await entity.delete();
                return null;
              }
            }
            // Touch last modified time for LRU tracking
            try {
              entity.setLastModifiedSync(DateTime.now());
            } catch (_) {}
            return entity;
          }
        }
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error looking up cached file: $e');
    }
    return null;
  }

  /// Returns a [File] reference inside the session cache directory for [nodeId].
  Future<File> getSessionFile(String nodeId, String extension) async {
    final dir = await getSessionDirectory();
    final safeExt = extension.startsWith('.') ? extension.substring(1) : extension;
    final fileName = safeExt.isNotEmpty ? 'session_$nodeId.$safeExt' : 'session_$nodeId';
    return File(p.join(dir.path, fileName));
  }

  /// Runs an LRU eviction pass to ensure the session cache stays within bounds.
  Future<void> evictLruIfNeeded() async {
    try {
      final dir = await getSessionDirectory();
      final files = dir.listSync().whereType<File>().toList();
      if (files.isEmpty) return;

      int totalBytes = 0;
      final fileStats = <File, int>{};
      for (final f in files) {
        final len = f.lengthSync();
        fileStats[f] = len;
        totalBytes += len;
      }

      if (totalBytes <= maxCacheSizeBytes && files.length <= maxCacheFiles) {
        return;
      }

      // Sort files by last modified timestamp (oldest first)
      files.sort((a, b) {
        try {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      for (final file in files) {
        if (totalBytes <= maxCacheSizeBytes && files.length <= maxCacheFiles) {
          break;
        }
        final size = fileStats[file] ?? 0;
        try {
          await file.delete();
          totalBytes -= size;
          files.remove(file);
          debugPrint('[SessionCacheService] Evicted LRU session file: ${file.path}');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[SessionCacheService] LRU eviction error: $e');
    }
  }

  /// Securely purges all decrypted files from the session cache.
  /// Called on App Lock, logout, or explicit cache clearance.
  Future<void> purge() async {
    try {
      final dir = await getSessionDirectory();
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
      debugPrint('[SessionCacheService] Successfully purged decrypted session cache');
    } catch (e) {
      debugPrint('[SessionCacheService] Error purging session cache: $e');
    }
  }

  /// Returns total disk bytes used by the current active session cache.
  Future<int> getSessionCacheSizeBytes() async {
    try {
      final dir = await getSessionDirectory();
      if (!await dir.exists()) return 0;
      int total = 0;
      for (final entity in dir.listSync()) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
