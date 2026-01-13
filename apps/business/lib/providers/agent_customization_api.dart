import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const _agentCustomizationBaseUrl = String.fromEnvironment(
  'AGENT_CUSTOMIZATION_BASE_URL',
  defaultValue:
      'https://agent-customization-service-230152279015.us-central1.run.app',
);

class ElevenLabsVoice {
  ElevenLabsVoice({required this.id, required this.name, this.labels});

  final String id;
  final String name;
  final Map<String, dynamic>? labels;

  factory ElevenLabsVoice.fromJson(Map<String, dynamic> json) {
    return ElevenLabsVoice(
      id: (json['voice_id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      labels: json['labels'] is Map ? (json['labels'] as Map).cast<String, dynamic>() : null,
    );
  }
}

class AgentCustomizationApi {
  final http.Client _client;
  AgentCustomizationApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<List<ElevenLabsVoice>> listVoices() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_agentCustomizationBaseUrl/v1/voices'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('List voices failed (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    final voices = (decoded is Map && decoded['voices'] is List)
        ? decoded['voices'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    return voices
        .whereType<Map>()
        .map((v) => ElevenLabsVoice.fromJson(v.cast<String, dynamic>()))
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  Future<ElevenLabsVoice> createVoice({
    required String name,
    required List<VoiceSampleUpload> files,
    String? description,
    Map<String, dynamic>? labels,
    bool removeBackgroundNoise = true,
  }) async {
    final token = await _token();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_agentCustomizationBaseUrl/v1/voices'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['name'] = name;
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }
    if (labels != null && labels.isNotEmpty) {
      request.fields['labels'] = jsonEncode(labels);
    }
    request.fields['remove_background_noise'] = removeBackgroundNoise ? 'true' : 'false';
    for (final sample in files) {
      request.files.add(http.MultipartFile.fromBytes(
        'files',
        sample.bytes,
        filename: sample.filename,
        contentType: MediaType.parse(sample.mimeType),
      ));
    }
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('Create voice failed (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final voiceId = (decoded['voice_id'] as String?)?.trim() ?? '';
    return ElevenLabsVoice(id: voiceId, name: name, labels: labels);
  }

  Future<Map<String, dynamic>> getStoreVoice(String storeId) async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_agentCustomizationBaseUrl/v1/stores/$storeId/voice'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Get voice failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> setStoreVoice({
    required String storeId,
    required String voiceId,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_agentCustomizationBaseUrl/v1/stores/$storeId/voice'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'voice_id': voiceId}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Apply voice failed (${resp.statusCode})');
    }
  }

  Future<Uint8List> previewVoice({
    required String voiceId,
    required String text,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_agentCustomizationBaseUrl/v1/voices/$voiceId/preview'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'text': text}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Preview failed (${resp.statusCode})');
    }
    return resp.bodyBytes;
  }
}

class VoiceSampleUpload {
  VoiceSampleUpload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}
