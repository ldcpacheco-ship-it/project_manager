import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

class PushNotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Envia o token via GET+base64 (mesmo esquema do app para evitar CORS/302).
  static Future<void> _enviarTokenParaPlanilha(String email, String token) async {
    try {
      final body = {'action': 'atualizarToken', 'email': email, 'token': token};
      final b64 = base64Url.encode(utf8.encode(json.encode(body)));
      final url = '$kScriptUrl?action=atualizarToken&payload=$b64';
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) debugPrint('Token sync HTTP ${r.statusCode}');
    } catch (e) {
      debugPrint('Erro ao sincronizar token: $e');
    }
  }

  static Future<void> registrarDispositivo(String emailUsuario) async {
    // 1. Solicita permissão (obrigatório para Android 13+ e iOS)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Obtém o Token exclusivo do aparelho
      String? token = await _fcm.getToken();

      if (token != null) {
        debugPrint("Token FCM capturado.");
        await _enviarTokenParaPlanilha(emailUsuario, token);
      }
    }
  }
}
