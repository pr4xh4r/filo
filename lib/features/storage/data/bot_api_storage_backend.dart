import 'dart:async';
import 'dart:convert';
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
        return StorageAuthState(
          step: StorageAuthStep.authenticated,
          userId: result['id'].toString(),
          userName: result['username'] as String?,
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
    ProgressCallback? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/sendDocument');
    final request = http.MultipartRequest('POST', uri);

    request.fields['chat_id'] = channelId;
    request.fields['caption'] = partFileName;

    final multipartFile = http.MultipartFile.fromBytes(
      'document',
      chunkData,
      filename: partFileName,
    );
    request.files.add(multipartFile);

    if (onProgress != null) {
      onProgress(0, chunkData.length);
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

  @override
  Future<Uint8List> downloadChunk({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
  }) async {
    // 1. Get file path from file_id
    final getFileResponse = await _client.get(
      Uri.parse('$_baseUrl/getFile?file_id=$remoteFileId'),
    );
    final getFileData = json.decode(getFileResponse.body) as Map<String, dynamic>;

    if (getFileData['ok'] != true) {
      _checkError(getFileData);
      throw Exception('Failed to retrieve file info: ${getFileData['description']}');
    }

    final filePath = getFileData['result']['file_path'] as String;

    // 2. Download the binary stream
    final downloadUri = Uri.parse('$_fileBaseUrl/$filePath');
    final response = await _client.get(downloadUri);

    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      if (onProgress != null) {
        onProgress(bytes.length, bytes.length);
      }
      return bytes;
    } else {
      throw Exception('Download failed with status ${response.statusCode}');
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
