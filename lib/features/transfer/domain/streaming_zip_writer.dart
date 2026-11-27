import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Metadata for a single completed entry written sequentially to a ZIP archive.
///
/// Persisted in export checkpoints so an interrupted archive build can truncate
/// trailing incomplete bytes and resume appending remaining files before
/// writing the Central Directory.
class StreamingZipEntry {
  final String nodeId;
  final String entryName;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int endOffset;
  final int modifiedAtMillis;

  const StreamingZipEntry({
    required this.nodeId,
    required this.entryName,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.endOffset,
    required this.modifiedAtMillis,
  });

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'entryName': entryName,
      'crc32': crc32,
      'compressedSize': compressedSize,
      'uncompressedSize': uncompressedSize,
      'localHeaderOffset': localHeaderOffset,
      'endOffset': endOffset,
      'modifiedAtMillis': modifiedAtMillis,
    };
  }

  factory StreamingZipEntry.fromJson(Map<String, dynamic> json) {
    return StreamingZipEntry(
      nodeId: json['nodeId'] as String,
      entryName: json['entryName'] as String,
      crc32: (json['crc32'] as num).toInt(),
      compressedSize: (json['compressedSize'] as num).toInt(),
      uncompressedSize: (json['uncompressedSize'] as num).toInt(),
      localHeaderOffset: (json['localHeaderOffset'] as num).toInt(),
      endOffset: (json['endOffset'] as num).toInt(),
      modifiedAtMillis: (json['modifiedAtMillis'] as num).toInt(),
    );
  }
}

/// Spec-compliant, constant-memory streaming ZIP / Zip64 writer (STORE method).
///
/// Key properties for multi-GB exports:
/// - Streams files in bounded 512 KB buffers directly to disk (constant ~1 MB RAM).
/// - Uses strictly sequential append I/O (`FileMode.append` after truncating to
///   [offset]) so POSIX `O_APPEND` never corrupts headers.
/// - Emits PKWARE APPNOTE-compliant Zip64 headers & Central Directory entries
///   whenever file size, archive offset, or entry count reaches Zip64 limits
///   (`>= 0xFFFFFFFF` or `>= 0xFFFF`).
/// - Supports checkpoint-based resume across interruptions.
class StreamingZipWriter {
  StreamingZipWriter._();

  static const int _localFileHeaderSig = 0x04034b50;
  static const int _centralFileHeaderSig = 0x02014b50;
  static const int _zip64EocdSig = 0x06064b50;
  static const int _zip64EocdLocatorSig = 0x07064b50;
  static const int _eocdSig = 0x06054b50;

  static const int _zip64ExtraId = 0x0001;
  static const int _utf8Flag = 1 << 11; // 2048
  static const int _methodStore = 0;
  static const int _versionStandard = 20;
  static const int _versionZip64 = 45;
  static const int _osMsdos = 0;

  static const int zip64Uint32Limit = 0xFFFFFFFF;
  static const int zip64Uint16Limit = 0xFFFF;
  static const int defaultBufferSize = 512 * 1024; // 512 KB

  /// Encodes DOS time/date fields from [dateTime].
  static ({int dosTime, int dosDate}) encodeDosDateTime(DateTime dateTime) {
    final utcOrLocal = dateTime;
    final year = utcOrLocal.year.clamp(1980, 2107);
    final dosTime = ((utcOrLocal.hour & 0x1F) << 11) |
        ((utcOrLocal.minute & 0x3F) << 5) |
        ((utcOrLocal.second ~/ 2) & 0x1F);
    final dosDate = (((year - 1980) & 0x7F) << 9) |
        ((utcOrLocal.month & 0x0F) << 5) |
        (utcOrLocal.day & 0x1F);
    return (dosTime: dosTime, dosDate: dosDate);
  }

  /// Appends a single file (or empty entry when [sourceFilePath] is null) to
  /// [archivePartPath] starting cleanly at [offset].
  ///
  /// Truncates any partial trailing bytes beyond [offset] first so resuming
  /// after an interrupted write is safe and deterministic.
  static Future<StreamingZipEntry> appendFile({
    required String archivePartPath,
    required int offset,
    required String nodeId,
    required String entryName,
    String? sourceFilePath,
    required DateTime modifiedAt,
    int bufferSize = defaultBufferSize,
    @visibleForTesting int sizeLimitForZip64 = zip64Uint32Limit,
  }) async {
    final normalizedName = entryName.replaceAll('\\', '/');
    final nameBytes = utf8.encode(normalizedName);

    final File? srcFile = sourceFilePath != null ? File(sourceFilePath) : null;
    final int size = srcFile != null ? await srcFile.length() : 0;

    // Pass 1: Compute CRC-32 sequentially in bounded slices so the Local File
    // Header can be written complete in one sequential append pass.
    int crc32 = 0;
    if (srcFile != null && size > 0) {
      final readRaf = await srcFile.open(mode: FileMode.read);
      try {
        final buffer = Uint8List(bufferSize);
        while (true) {
          final bytesRead = await readRaf.readInto(buffer);
          if (bytesRead <= 0) break;
          crc32 = getCrc32(Uint8List.sublistView(buffer, 0, bytesRead), crc32);
        }
      } finally {
        await readRaf.close();
      }
    }

    final needsZip64 = size >= sizeLimitForZip64;
    final dos = encodeDosDateTime(modifiedAt);
    final extraBytes = needsZip64
        ? buildZip64ExtraField(
            uncompressedSize: size,
            compressedSize: size,
          )
        : Uint8List(0);

    final header = _buildLocalFileHeader(
      nameBytes: nameBytes,
      extraBytes: extraBytes,
      dosTime: dos.dosTime,
      dosDate: dos.dosDate,
      crc32: crc32,
      compressedSize: needsZip64 ? zip64Uint32Limit : size,
      uncompressedSize: needsZip64 ? zip64Uint32Limit : size,
      versionNeeded: needsZip64 ? _versionZip64 : _versionStandard,
    );

    final partFile = File(archivePartPath);
    if (!partFile.parent.existsSync()) {
      partFile.parent.createSync(recursive: true);
    }

    final zipRaf = await partFile.open(mode: FileMode.append);
    int bytesWritten = 0;
    try {
      final existingLen = await zipRaf.length();
      if (offset < 0 || offset > existingLen) {
        throw RangeError(
          'Invalid resume offset $offset for archive length $existingLen',
        );
      }
      if (existingLen != offset) {
        await zipRaf.truncate(offset);
      }
      await zipRaf.setPosition(offset);

      await zipRaf.writeFrom(header);

      if (srcFile != null && size > 0) {
        final readRaf = await srcFile.open(mode: FileMode.read);
        try {
          final buffer = Uint8List(bufferSize);
          while (true) {
            final bytesRead = await readRaf.readInto(buffer);
            if (bytesRead <= 0) break;
            await zipRaf.writeFrom(buffer, 0, bytesRead);
            bytesWritten += bytesRead;
          }
        } finally {
          await readRaf.close();
        }
      }

      if (bytesWritten != size) {
        throw StateError(
          'File size changed during archive write for $normalizedName: '
          'expected $size bytes, wrote $bytesWritten bytes',
        );
      }

      await zipRaf.flush();
    } finally {
      await zipRaf.close();
    }

    final endOffset = offset + header.length + bytesWritten;
    return StreamingZipEntry(
      nodeId: nodeId,
      entryName: normalizedName,
      crc32: crc32,
      compressedSize: size,
      uncompressedSize: size,
      localHeaderOffset: offset,
      endOffset: endOffset,
      modifiedAtMillis: modifiedAt.millisecondsSinceEpoch,
    );
  }

  /// Appends the Central Directory, optional Zip64 EOCD + Locator, and EOCD
  /// to [archivePartPath] starting at [centralDirectoryOffset].
  static Future<void> finalize({
    required String archivePartPath,
    required List<StreamingZipEntry> entries,
    required int centralDirectoryOffset,
    String comment = '',
    @visibleForTesting int sizeLimitForZip64 = zip64Uint32Limit,
    @visibleForTesting int entryLimitForZip64 = zip64Uint16Limit,
  }) async {
    final partFile = File(archivePartPath);
    final zipRaf = await partFile.open(mode: FileMode.append);
    try {
      final existingLen = await zipRaf.length();
      if (centralDirectoryOffset < 0 || centralDirectoryOffset > existingLen) {
        throw RangeError(
          'Invalid central directory offset $centralDirectoryOffset for length $existingLen',
        );
      }
      if (existingLen != centralDirectoryOffset) {
        await zipRaf.truncate(centralDirectoryOffset);
      }
      await zipRaf.setPosition(centralDirectoryOffset);

      final cdBuilder = BytesBuilder(copy: false);
      bool zipNeedsZip64 = false;

      for (final entry in entries) {
        final needUncomp64 = entry.uncompressedSize >= sizeLimitForZip64;
        final needComp64 = entry.compressedSize >= sizeLimitForZip64;
        final needOffset64 = entry.localHeaderOffset >= sizeLimitForZip64;
        final entryNeedsZip64 = needUncomp64 || needComp64 || needOffset64;
        zipNeedsZip64 |= entryNeedsZip64;

        final nameBytes = utf8.encode(entry.entryName);
        final extraBytes = entryNeedsZip64
            ? buildZip64ExtraField(
                uncompressedSize: needUncomp64 ? entry.uncompressedSize : null,
                compressedSize: needComp64 ? entry.compressedSize : null,
                localHeaderOffset: needOffset64 ? entry.localHeaderOffset : null,
              )
            : Uint8List(0);

        final dos = encodeDosDateTime(
          DateTime.fromMillisecondsSinceEpoch(entry.modifiedAtMillis),
        );

        final version = entryNeedsZip64 ? _versionZip64 : _versionStandard;
        final versionMadeBy = (_osMsdos << 8) | version;

        final cdHeader = ByteData(46);
        cdHeader.setUint32(0, _centralFileHeaderSig, Endian.little);
        cdHeader.setUint16(4, versionMadeBy, Endian.little);
        cdHeader.setUint16(6, version, Endian.little);
        cdHeader.setUint16(8, _utf8Flag, Endian.little);
        cdHeader.setUint16(10, _methodStore, Endian.little);
        cdHeader.setUint16(12, dos.dosTime, Endian.little);
        cdHeader.setUint16(14, dos.dosDate, Endian.little);
        cdHeader.setUint32(16, entry.crc32, Endian.little);
        cdHeader.setUint32(
          20,
          needComp64 ? zip64Uint32Limit : entry.compressedSize,
          Endian.little,
        );
        cdHeader.setUint32(
          24,
          needUncomp64 ? zip64Uint32Limit : entry.uncompressedSize,
          Endian.little,
        );
        cdHeader.setUint16(28, nameBytes.length, Endian.little);
        cdHeader.setUint16(30, extraBytes.length, Endian.little);
        cdHeader.setUint16(32, 0, Endian.little); // comment len
        cdHeader.setUint16(34, 0, Endian.little); // disk start
        cdHeader.setUint16(36, 0, Endian.little); // internal attrs
        cdHeader.setUint32(38, 0, Endian.little); // external attrs
        cdHeader.setUint32(
          42,
          needOffset64 ? zip64Uint32Limit : entry.localHeaderOffset,
          Endian.little,
        );

        cdBuilder.add(cdHeader.buffer.asUint8List());
        cdBuilder.add(nameBytes);
        if (extraBytes.isNotEmpty) {
          cdBuilder.add(extraBytes);
        }
      }

      final cdBytes = cdBuilder.toBytes();
      final centralDirSize = cdBytes.length;
      await zipRaf.writeFrom(cdBytes);

      final count = entries.length;
      final needZip64Count = count >= entryLimitForZip64;
      final needZip64CdSize = centralDirSize >= sizeLimitForZip64;
      final needZip64CdOffset = centralDirectoryOffset >= sizeLimitForZip64;
      final archiveNeedsZip64 = zipNeedsZip64 ||
          needZip64Count ||
          needZip64CdSize ||
          needZip64CdOffset;

      if (archiveNeedsZip64) {
        final zip64EocdOffset = centralDirectoryOffset + centralDirSize;
        final z64Eocd = ByteData(56);
        z64Eocd.setUint32(0, _zip64EocdSig, Endian.little);
        z64Eocd.setUint64(4, 44, Endian.little); // remaining record size
        z64Eocd.setUint16(12, _versionZip64, Endian.little);
        z64Eocd.setUint16(14, _versionZip64, Endian.little);
        z64Eocd.setUint32(16, 0, Endian.little); // disk number
        z64Eocd.setUint32(20, 0, Endian.little); // disk with CD
        z64Eocd.setUint64(24, count, Endian.little);
        z64Eocd.setUint64(32, count, Endian.little);
        z64Eocd.setUint64(40, centralDirSize, Endian.little);
        z64Eocd.setUint64(48, centralDirectoryOffset, Endian.little);
        await zipRaf.writeFrom(z64Eocd.buffer.asUint8List());

        final locator = ByteData(20);
        locator.setUint32(0, _zip64EocdLocatorSig, Endian.little);
        locator.setUint32(4, 0, Endian.little); // disk with Zip64 EOCD
        locator.setUint64(8, zip64EocdOffset, Endian.little);
        locator.setUint32(16, 1, Endian.little); // total disks
        await zipRaf.writeFrom(locator.buffer.asUint8List());
      }

      final commentBytes = comment.isEmpty ? Uint8List(0) : utf8.encode(comment);
      final eocd = ByteData(22);
      eocd.setUint32(0, _eocdSig, Endian.little);
      eocd.setUint16(4, 0, Endian.little); // disk number
      eocd.setUint16(6, 0, Endian.little); // CD start disk
      eocd.setUint16(
        8,
        needZip64Count ? zip64Uint16Limit : count,
        Endian.little,
      );
      eocd.setUint16(
        10,
        needZip64Count ? zip64Uint16Limit : count,
        Endian.little,
      );
      eocd.setUint32(
        12,
        needZip64CdSize ? zip64Uint32Limit : centralDirSize,
        Endian.little,
      );
      eocd.setUint32(
        16,
        needZip64CdOffset ? zip64Uint32Limit : centralDirectoryOffset,
        Endian.little,
      );
      eocd.setUint16(20, commentBytes.length, Endian.little);

      await zipRaf.writeFrom(eocd.buffer.asUint8List());
      if (commentBytes.isNotEmpty) {
        await zipRaf.writeFrom(commentBytes);
      }

      await zipRaf.flush();
    } finally {
      await zipRaf.close();
    }
  }

  static Uint8List _buildLocalFileHeader({
    required List<int> nameBytes,
    required Uint8List extraBytes,
    required int dosTime,
    required int dosDate,
    required int crc32,
    required int compressedSize,
    required int uncompressedSize,
    required int versionNeeded,
  }) {
    final bd = ByteData(30);
    bd.setUint32(0, _localFileHeaderSig, Endian.little);
    bd.setUint16(4, versionNeeded, Endian.little);
    bd.setUint16(6, _utf8Flag, Endian.little);
    bd.setUint16(8, _methodStore, Endian.little);
    bd.setUint16(10, dosTime, Endian.little);
    bd.setUint16(12, dosDate, Endian.little);
    bd.setUint32(14, crc32, Endian.little);
    bd.setUint32(18, compressedSize, Endian.little);
    bd.setUint32(22, uncompressedSize, Endian.little);
    bd.setUint16(26, nameBytes.length, Endian.little);
    bd.setUint16(28, extraBytes.length, Endian.little);

    final out = Uint8List(30 + nameBytes.length + extraBytes.length);
    out.setRange(0, 30, bd.buffer.asUint8List());
    out.setRange(30, 30 + nameBytes.length, nameBytes);
    if (extraBytes.isNotEmpty) {
      out.setRange(30 + nameBytes.length, out.length, extraBytes);
    }
    return out;
  }

  /// Builds a PKWARE APPNOTE 4.5.3-compliant Zip64 extra field containing only
  /// the 64-bit fields whose corresponding 32-bit header field is `0xFFFFFFFF`.
  @visibleForTesting
  static Uint8List buildZip64ExtraField({
    int? uncompressedSize,
    int? compressedSize,
    int? localHeaderOffset,
  }) {
    final payloadBytes = (uncompressedSize != null ? 8 : 0) +
        (compressedSize != null ? 8 : 0) +
        (localHeaderOffset != null ? 8 : 0);
    final bd = ByteData(4 + payloadBytes);
    bd.setUint16(0, _zip64ExtraId, Endian.little);
    bd.setUint16(2, payloadBytes, Endian.little);

    int pos = 4;
    if (uncompressedSize != null) {
      bd.setUint64(pos, uncompressedSize, Endian.little);
      pos += 8;
    }
    if (compressedSize != null) {
      bd.setUint64(pos, compressedSize, Endian.little);
      pos += 8;
    }
    if (localHeaderOffset != null) {
      bd.setUint64(pos, localHeaderOffset, Endian.little);
      pos += 8;
    }
    return bd.buffer.asUint8List();
  }
}
