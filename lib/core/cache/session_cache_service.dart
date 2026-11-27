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
  static const int _zeroChunkSize = 64 * 1024; // 64 KB chunk buffer to avoid OOM on large files
  static final Uint8List _zeroBuffer = Uint8List(_zeroChunkSize);
  static const List<String> _staleTempPrefixes = [
    'filo_vid_',
    'filo_preview_',
    'filo_stream_',
    'filo_share_',
    'filo_backup_export_',
  ];

  Directory? _cachedSessionDir;
  bool _isOverrideDir = false;

  @visibleForTesting
  void setOverrideDirectory(Directory? dir) {
    _cachedSessionDir = dir;
    _isOverrideDir = dir != null;
  }

  /// Overwrites [file] in-place with zeros using a 64 KB chunk buffer, truncates
  /// its length to 0, and deletes it from disk.
  ///
  /// Uses [FileMode.writeOnlyAppend] with [RandomAccessFile.setPosition] at 0
  /// so existing logical blocks are overwritten in-place without truncating
  /// first or doubling allocated disk space. Note that on flash storage
  /// (eMMC/UFS/SSD), FTL wear-leveling may remap physical writes until TRIM/GC.
  static Future<void> secureDeleteFile(File file) async {
    if (!await file.exists()) return;
    RandomAccessFile? raf;
    try {
      final length = await file.length();
      if (length > 0) {
        raf = await file.open(mode: FileMode.writeOnlyAppend);
        await raf.setPosition(0);
        int remaining = length;
        while (remaining > 0) {
          final chunkLen = remaining < _zeroChunkSize ? remaining : _zeroChunkSize;
          await raf.writeFrom(_zeroBuffer, 0, chunkLen);
          remaining -= chunkLen;
        }
        await raf.flush();
        await raf.truncate(0);
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error zeroing file ${file.path}: $e');
    } finally {
      try {
        await raf?.close();
      } catch (e) {
        debugPrint('[SessionCacheService] Error closing file handle ${file.path}: $e');
      }
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error deleting file ${file.path}: $e');
    }
  }

  /// Synchronous counterpart to [secureDeleteFile] for synchronous cleanup paths.
  static void secureDeleteFileSync(File file) {
    if (!file.existsSync()) return;
    RandomAccessFile? raf;
    try {
      final length = file.lengthSync();
      if (length > 0) {
        raf = file.openSync(mode: FileMode.writeOnlyAppend);
        raf.setPositionSync(0);
        int remaining = length;
        while (remaining > 0) {
          final chunkLen = remaining < _zeroChunkSize ? remaining : _zeroChunkSize;
          raf.writeFromSync(_zeroBuffer, 0, chunkLen);
          remaining -= chunkLen;
        }
        raf.flushSync();
        raf.truncateSync(0);
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error zeroing file ${file.path}: $e');
    } finally {
      try {
        raf?.closeSync();
      } catch (e) {
        debugPrint('[SessionCacheService] Error closing file handle ${file.path}: $e');
      }
    }
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error deleting file ${file.path}: $e');
    }
  }

  /// Recursively overwrites and deletes all files inside [dir], then removes [dir].
  static Future<void> secureDeleteDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      final entities = await dir.list(recursive: true, followLinks: false).toList();
      for (final entity in entities) {
        if (entity is File) {
          await secureDeleteFile(entity);
        }
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error traversing directory ${dir.path}: $e');
    }
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[SessionCacheService] Error deleting directory ${dir.path}: $e');
    }
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
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final base = p.basename(entity.path);
          if (base.startsWith('session_$nodeId.') || base == 'session_$nodeId') {
            if (expectedSize != null && expectedSize > 0) {
              if (entity.lengthSync() != expectedSize) {
                // Incomplete or corrupted stream, securely remove it
                await secureDeleteFile(entity);
                return null;
              }
            }
            // Touch last modified time for LRU tracking
            try {
              entity.setLastModifiedSync(DateTime.now());
            } catch (e) {
              debugPrint('[SessionCacheService] Failed to update mtime for ${entity.path}: $e');
            }
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
      final files = dir.listSync(followLinks: false).whereType<File>().toList();
      if (files.isEmpty) return;

      int totalBytes = 0;
      final fileStats = <File, int>{};
      for (final f in files) {
        final len = f.lengthSync();
        fileStats[f] = len;
        totalBytes += len;
      }

      int remainingFiles = files.length;
      if (totalBytes <= maxCacheSizeBytes && remainingFiles <= maxCacheFiles) {
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
        if (totalBytes <= maxCacheSizeBytes && remainingFiles <= maxCacheFiles) {
          break;
        }
        final size = fileStats[file] ?? 0;
        try {
          await secureDeleteFile(file);
          totalBytes -= size;
          remainingFiles--;
          debugPrint('[SessionCacheService] Evicted LRU session file: ${file.path}');
        } catch (e) {
          debugPrint('[SessionCacheService] Failed to evict ${file.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('[SessionCacheService] LRU eviction error: $e');
    }
  }

  /// Securely purges all decrypted files from the session cache.
  /// Called on App Lock, logout, startup recovery, or explicit cache clearance.
  Future<void> purge() async {
    try {
      final dir = await getSessionDirectory();
      if (await dir.exists()) {
        final entities = await dir.list(recursive: false, followLinks: false).toList();
        for (final entity in entities) {
          try {
            if (entity is File) {
              await secureDeleteFile(entity);
            } else if (entity is Directory) {
              await secureDeleteDirectory(entity);
            }
          } catch (e) {
            debugPrint('[SessionCacheService] Error purging ${entity.path}: $e');
          }
        }
      }
      if (!_isOverrideDir && await dir.parent.exists()) {
        final tempEntities = await dir.parent.list(recursive: false, followLinks: false).toList();
        for (final entity in tempEntities) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (_staleTempPrefixes.any(name.startsWith)) {
              await secureDeleteFile(entity);
            }
          }
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
      for (final entity in dir.listSync(followLinks: false)) {
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
