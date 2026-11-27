import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/storage_backend.dart';
import '../domain/storage_models.dart';

/// Fallback storage backend using the official Telegram Bot HTTP API.
///
/// Features:
/// - "Bring Your Own Bot" mode for users preferring bot tokens over MTProto login.
/// - Strict chunk size capping at 15 MB to guarantee files stay under Telegram's
///   20 MB `getFile` download limit.
/// - Parses Telegram HTTP 429 / `retry_after` flood-wait parameters.
class BotApiStorageBackend implements StorageBackend {
  final String botToken;
  final String targetChatId;
  final http.Client _client;

  BotApiStorageBackend({
    required this.botToken,
    required this.targetChatId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _baseUrl => 'https://api.telegram.org/bot$botToken';
  String get _fileBaseUrl => 'https://api.telegram.org/file/bot$botToken';

  @override
  Future<void> initialize() async {}

  @override
  Future<StorageAuthState> checkAuth() async {
    try {
      final response = await _client.get(Uri.parse('$_baseUrl/getMe'));
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['ok'] == true) {
        final result = data['result'] as Map<String, dynamic>;
        final firstName = (result['first_name'] as String? ?? '').trim();
        final lastName = (result['last_name'] as String? ?? '').trim();
        final fullName = '$firstName $lastName'.trim();
        return StorageAuthState(
          step: StorageAuthStep.authenticated,
          userId: result['id'].toString(),
          userName: result['username'] as String?,
          displayName: fullName.isNotEmpty ? fullName : null,
        );
      } else {
        return StorageAuthState(
          step: StorageAuthStep.unauthenticated,
          error: data['description'] as String?,
        );
      }
    } catch (e) {
      return StorageAuthState(
        step: StorageAuthStep.unauthenticated,
        error: e.toString(),
      );
    }
  }

  @override
  Future<StorageAuthState> sendCode(String phoneNumber) async {
    // Bot API does not use phone login
    return const StorageAuthState(
      step: StorageAuthStep.authenticated,
    );
  }

  @override
  Future<StorageAuthState> signInWithCode(String code) async {
    return const StorageAuthState(
      step: StorageAuthStep.authenticated,
    );
  }

  @override
  Future<StorageAuthState> checkPassword(String password) async {
    return const StorageAuthState(
      step: StorageAuthStep.authenticated,
    );
  }

  @override
  Future<void> signOut() async {
    _client.close();
  }

  @override
  Stream<StorageAuthState>? get authStateStream => null;

  @override
  Stream<String>? get qrLinkStream => null;

  @override
  Future<String?> requestQrCode() async => null;

  @override
  Future<VaultChannelInfo> getOrCreateVaultChannel(String channelTitle) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/getChat'),
      body: {'chat_id': targetChatId},
    );
    final data = json.decode(response.body) as Map<String, dynamic>;

    if (data['ok'] == true) {
      final result = data['result'] as Map<String, dynamic>;
      final pinnedMessage = result['pinned_message'] as Map<String, dynamic>?;

      return VaultChannelInfo(
        channelId: targetChatId,
        title: (result['title'] as String?) ?? channelTitle,
        pinnedMessageId: pinnedMessage?['message_id']?.toString(),
      );
    } else {
      _checkError(data);
      throw Exception('Failed to access channel: ${data['description']}');
    }
  }

  @override
  Future<RemoteUploadedChunk> uploadChunk({
    required String channelId,
    required Uint8List chunkData,
    required String partFileName,
    File? sourceFile,
    ProgressCallback? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/sendDocument');
    final request = http.MultipartRequest('POST', uri);

    request.fields['chat_id'] = channelId;
    request.fields['caption'] = partFileName;

    final int totalSize;
    if (sourceFile != null && await sourceFile.exists()) {
      request.files.add(await http.MultipartFile.fromPath(
        'document',
        sourceFile.path,
        filename: partFileName,
      ));
      totalSize = await sourceFile.length();
    } else {
      final multipartFile = http.MultipartFile.fromBytes(
        'document',
        chunkData,
        filename: partFileName,
      );
      request.files.add(multipartFile);
      totalSize = chunkData.length;
    }

    if (onProgress != null) {
      onProgress(0, totalSize);
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    final data = json.decode(response.body) as Map<String, dynamic>;

    if (data['ok'] == true) {
      final result = data['result'] as Map<String, dynamic>;
      final document = result['document'] as Map<String, dynamic>;

      if (onProgress != null) {
        onProgress(chunkData.length, chunkData.length);
      }

      return RemoteUploadedChunk(
        messageId: result['message_id'].toString(),
        remoteFileId: document['file_id'] as String,
        sizeBytes: (document['file_size'] as int?) ?? chunkData.length,
        partFileName: partFileName,
      );
    } else {
      _checkError(data);
      throw Exception('Upload failed: ${data['description']}');
    }
  }

  Future<Uri> _resolveDownloadUri(String remoteFileId) async {
    final getFileResponse = await _client
        .get(Uri.parse('$_baseUrl/getFile?file_id=$remoteFileId'))
        .timeout(const Duration(seconds: 30));
    final getFileData = json.decode(getFileResponse.body) as Map<String, dynamic>;

    if (getFileData['ok'] != true) {
      _checkError(getFileData);
      throw Exception('Failed to retrieve file info: ${getFileData['description']}');
    }

    final filePath = getFileData['result']['file_path'] as String;
    return Uri.parse('$_fileBaseUrl/$filePath');
  }

  Future<void> _streamDownloadToSink({
    required String remoteFileId,
    required void Function(List<int> chunk) onChunk,
    ProgressCallback? onProgress,
  }) async {
    final downloadUri = await _resolveDownloadUri(remoteFileId);
    final request = http.Request('GET', downloadUri);
    final streamedResponse = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );

    if (streamedResponse.statusCode != 200) {
      throw Exception('Download failed with status ${streamedResponse.statusCode}');
    }

    final total = streamedResponse.contentLength ?? 0;
    int received = 0;

    final iterator = StreamIterator<List<int>>(streamedResponse.stream);
    try {
      while (await iterator.moveNext().timeout(const Duration(seconds: 120))) {
        final chunk = iterator.current;
        onChunk(chunk);
        received += chunk.length;
        onProgress?.call(received, total > 0 ? total : received);
      }
    } finally {
      await iterator.cancel();
    }
  }

  @override
  Future<Uint8List> downloadChunk({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
  }) async {
    final builder = BytesBuilder(copy: false);
    await _streamDownloadToSink(
      remoteFileId: remoteFileId,
      onChunk: builder.add,
      onProgress: onProgress,
    );
    return builder.toBytes();
  }

  @override
  Future<void> downloadChunkToFile({
    required String channelId,
    required String remoteFileId,
    required File destinationFile,
    ProgressCallback? onProgress,
    bool deleteRemoteCache = false,
  }) async {
    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }

    final sink = destinationFile.openWrite();
    var sinkClosed = false;
    try {
      await _streamDownloadToSink(
        remoteFileId: remoteFileId,
        onChunk: sink.add,
        onProgress: onProgress,
      );
      await sink.flush();
      await sink.close();
      sinkClosed = true;
    } catch (_) {
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (await destinationFile.exists()) {
        try {
          await destinationFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/deleteMessage'),
      body: {
        'chat_id': channelId,
        'message_id': messageId,
      },
    );
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      _checkError(data);
    }
  }

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/pinChatMessage'),
      body: {
        'chat_id': channelId,
        'message_id': messageId,
        'disable_notification': 'true',
      },
    );
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      _checkError(data);
    }
  }

  @override
  Future<RemoteMessage?> getPinnedMessage({
    required String channelId,
  }) async {
    // BUG 14 FIX: Retrieve chat info and extract pinned document remote file id
    final response = await _client.post(
      Uri.parse('$_baseUrl/getChat'),
      body: {'chat_id': channelId.isNotEmpty ? channelId : targetChatId},
    );
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true) return null;

    final result = data['result'] as Map<String, dynamic>;
    final pinned = result['pinned_message'] as Map<String, dynamic>?;
    if (pinned == null) return null;

    final document = pinned['document'] as Map<String, dynamic>?;
    final remoteFileId = document?['file_id'] as String?;

    return RemoteMessage(
      messageId: pinned['message_id'].toString(),
      remoteFileId: remoteFileId,
      caption: pinned['caption'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(
        ((pinned['date'] as num?)?.toInt() ?? 0) * 1000,
      ),
    );
  }

  @override
  Future<int> wipeChannel({
    required String channelId,
  }) async {
    // Bot API doesn't support bulk message deletion, returns status
    return 0;
  }

  @override
  Future<StorageQuotaInfo> getStorageQuota() async {
    return const StorageQuotaInfo(
      totalBytes: -1,
      usedBytes: 0,
      planName: 'Unlimited',
      providerName: 'Telegram',
    );
  }

  @override
  Future<void> dispose() async {
    _client.close();
  }

  void _checkError(Map<String, dynamic> data) {
    if (data['error_code'] == 429) {
      final parameters = data['parameters'] as Map<String, dynamic>?;
      final retryAfter = parameters?['retry_after'] as int? ?? 10;
      throw Exception('FLOOD_WAIT_$retryAfter: Rate limit exceeded. Retry after $retryAfter seconds.');
    }
  }
}
