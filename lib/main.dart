import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

const String kScriptUrl = "https://script.google.com/macros/s/AKfycbxaMMdfTsEV_gUd0Bg2l5D666FqUVEn5wynNyT_Cdt_iY4mg0zxbtzfFVlAeb87IzfqsQ/exec";

bool isPerfilGerencial(Map<String, dynamic> usuario) {
  final p = (usuario['Perfil'] ?? usuario['perfil'] ?? usuario['Función'] ?? usuario['Funcao'] ?? '')
      .toString().trim().toLowerCase();
  const gerenciales = ['gerente', 'coordenador', 'coordinador', 'manager', 'supervisor'];
  return gerenciales.any((g) => p.contains(g));
}

/// Perfis que podem acessar GESTION (gestionar programações): Coordenador, Gerentes, Directores.
bool isPerfilGestion(Map<String, dynamic> usuario) {
  final p = (usuario['Perfil'] ?? usuario['perfil'] ?? usuario['Función'] ?? usuario['Funcao'] ?? '')
      .toString().trim().toLowerCase();
  const gestores = ['coordenador', 'coordinador', 'gerente', 'manager', 'director'];
  return gestores.any((g) => p.contains(g));
}

/// Parâmetros para fetch por perfil: Director/Gerente/Coordinador=todos; Ejecutor=por responsable; Solicitante=por email.
({String? email, String? responsable}) parametrosFetchPorPerfil(Map<String, dynamic> usuario) {
  final p = (usuario['Perfil'] ?? usuario['perfil'] ?? usuario['Función'] ?? usuario['Funcao'] ?? '')
      .toString().trim().toLowerCase();
  if (p.contains('director') || p.contains('gerente') || p.contains('manager') || p.contains('coordenador') || p.contains('coordinador')) {
    return (email: null, responsable: null);
  }
  if (p.contains('ejecutor')) {
    final nombre = (usuario['Nombre'] ?? usuario['nombre'] ?? usuario['Name'] ?? '').toString().trim();
    return (email: null, responsable: nombre.isNotEmpty ? nombre : null);
  }
  final email = (usuario['Email'] ?? usuario['email'] ?? usuario['Correo'] ?? '').toString().trim().toLowerCase();
  return (email: email.isNotEmpty ? email : null, responsable: null);
}

Future<Map<String, dynamic>> _httpGet(String url) async {
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      debugPrint('HTTP GET $url status ${r.statusCode}');
      return {'success': false, 'message': 'Error de conexión', 'data': null};
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    if (j.containsKey('success')) {
      return {'success': j['success'] == true, 'message': (j['message'] ?? '').toString(), 'data': j['data']};
    }
    return {'success': true, 'message': '', 'data': j};
  } catch (e, st) {
    debugPrint('HTTP GET error: $e\n$st');
    return {'success': false, 'message': e.toString(), 'data': null};
  }
}

Future<Map<String, dynamic>> _httpPost(String url, Map<String, dynamic> body) async {
  try {
    final r = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      debugPrint('HTTP POST $url status ${r.statusCode} body: ${r.body}');
      String msg = 'Error de conexión';
      if (r.statusCode == 404) {
        msg = 'Servidor no encontrado (404). Verifique que el script de Google Apps esté desplegado correctamente.';
      } else if (r.statusCode == 500) {
        msg = 'Error del servidor (500). Revise el backend de Google Apps Script.';
      } else if (r.statusCode >= 400) {
        msg = 'Error de conexión (código ${r.statusCode}).';
      }
      return {'success': false, 'message': msg, 'data': null};
    }
    dynamic j;
    try {
      j = json.decode(r.body);
    } catch (_) {
      debugPrint('HTTP POST: respuesta no es JSON válido: ${r.body}');
      return {'success': false, 'message': 'Respuesta inválida del servidor.', 'data': null};
    }
    if (j is Map<String, dynamic>) {
      if (j.containsKey('success')) {
        return {'success': j['success'] == true, 'message': (j['message'] ?? '').toString(), 'data': j['data']};
      }
      return {'success': j['status'] == 'success', 'message': (j['message'] ?? '').toString(), 'data': j};
    }
    return {'success': false, 'message': 'Respuesta inválida del servidor.', 'data': null};
  } catch (e, st) {
    debugPrint('HTTP POST error: $e\n$st');
    String msg = 'Error de conexión. Verifique su conexión a internet.';
    if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
      msg = 'Sin conexión a internet. Verifique su red.';
    } else if (e.toString().contains('TimeoutException')) {
      msg = 'Tiempo de espera agotado. Intente de nuevo.';
    }
    return {'success': false, 'message': msg, 'data': null};
  }
}

List<Map<String, dynamic>> _extrairDemandas(dynamic data) {
  if (data == null) return [];
  if (data is Map && data['demandas'] != null) {
    return List<Map<String, dynamic>>.from(
        (data['demandas'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }
  if (data is List) {
    return List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
  }
  return [];
}

/// Parâmetros de filtro por perfil: Director/Gerente=todos; Coordinador=todos;
/// Ejecutor=por responsable (nome); Solicitante=por email do solicitante.
Future<List<Map<String, dynamic>>> fetchDemandas(String sector, {String? email, String? perfil, String? responsable}) async {
  var url = "$kScriptUrl?action=getDemandas&sector=${Uri.encodeComponent(sector)}";
  if (perfil != null && perfil.trim().isNotEmpty) {
    url += "&perfil=${Uri.encodeComponent(perfil.trim())}";
  }
  if (email != null && email.trim().isNotEmpty) {
    url += "&email=${Uri.encodeComponent(email.trim().toLowerCase())}";
  }
  if (responsable != null && responsable.trim().isNotEmpty) {
    url += "&responsable=${Uri.encodeComponent(responsable.trim())}";
  }
  final res = await _httpGet(url);
  if (res['success'] != true) return [];
  return _extrairDemandas(res['data']);
}

Future<List<Map<String, dynamic>>> fetchDemandasGestion(String sector, {String? perfil, String? email, String? responsable}) async {
  var url = "$kScriptUrl?action=getDemandasGestion&sector=${Uri.encodeComponent(sector)}";
  if (perfil != null && perfil.trim().isNotEmpty) {
    url += "&perfil=${Uri.encodeComponent(perfil.trim())}";
  }
  if (email != null && email.trim().isNotEmpty) {
    url += "&email=${Uri.encodeComponent(email.trim().toLowerCase())}";
  }
  if (responsable != null && responsable.trim().isNotEmpty) {
    url += "&responsable=${Uri.encodeComponent(responsable.trim())}";
  }
  final res = await _httpGet(url);
  if (res['success'] != true) return [];
  return _extrairDemandas(res['data']);
}

Future<List<Map<String, dynamic>>> fetchDemandasAgenda(String sector, {String? email, String? perfil, String? responsable}) async {
  var url = "$kScriptUrl?action=getDemandasAgenda&sector=${Uri.encodeComponent(sector)}";
  if (perfil != null && perfil.trim().isNotEmpty) {
    url += "&perfil=${Uri.encodeComponent(perfil.trim())}";
  }
  if (email != null && email.trim().isNotEmpty) {
    url += "&email=${Uri.encodeComponent(email.trim().toLowerCase())}";
  }
  if (responsable != null && responsable.trim().isNotEmpty) {
    url += "&responsable=${Uri.encodeComponent(responsable.trim())}";
  }
  final res = await _httpGet(url);
  if (res['success'] != true) return [];
  return _extrairDemandas(res['data']);
}

Future<Map<String, int>> fetchKPIs(String sector) async {
  final res = await _httpGet("$kScriptUrl?action=getKPIs&sector=${Uri.encodeComponent(sector)}");
  if (res['success'] != true) return {'total': 0, 'pendentes': 0, 'resolvidas': 0};
  final d = res['data'] as Map<String, dynamic>?;
  if (d == null) return {'total': 0, 'pendentes': 0, 'resolvidas': 0};
  return {
    'total': (d['total'] is num) ? (d['total'] as num).toInt() : 0,
    'pendentes': (d['pendentesProgramacao'] is num) ? (d['pendentesProgramacao'] as num).toInt() : 0,
    'resolvidas': (d['resolvidas'] is num) ? (d['resolvidas'] as num).toInt() : 0,
  };
}

Future<Map<String, dynamic>> crearDemanda(Map<String, dynamic> dados) async {
  final res = await _httpPost(kScriptUrl, {'action': 'salvarDemanda', 'dados': dados});
  return {'ok': res['success'] == true, 'message': (res['message'] ?? '').toString()};
}

Future<Map<String, dynamic>> crearDemandaReprogramada(Map<String, dynamic> dados) async {
  final res = await _httpPost(kScriptUrl, {'action': 'reprogramarDemanda', 'dados': dados});
  return {'ok': res['success'] == true, 'message': (res['message'] ?? '').toString()};
}

Future<bool> crearDemandaCancelada(Map<String, dynamic> dados) async {
  final res = await _httpPost(kScriptUrl, {'action': 'crearDemandaCancelada', 'dados': dados});
  return res['success'] == true;
}

Future<List<String>> fetchLocais() async {
  final res = await _httpGet("$kScriptUrl?action=getLocais");
  if (res['success'] != true) return ['Ponte Jarabacoa', 'Jaguey', 'Retorno San Francisco', 'Marginal San Francisco', 'Otro'];
  final d = res['data'] as Map<String, dynamic>?;
  final loc = d?['locais'] as List?;
  if (loc == null || loc.isEmpty) return ['Ponte Jarabacoa', 'Jaguey', 'Retorno San Francisco', 'Marginal San Francisco', 'Otro'];
  return List<String>.from(loc.map((e) => e.toString()));
}

/// Sectores únicos da coluna "Sector Solicitante" na planilha.
Future<List<String>> fetchSectores() async {
  final res = await _httpGet("$kScriptUrl?action=getSectores");
  if (res['success'] != true) return ['Producción', 'Diseño', 'Comercial', 'Calidad', 'Ingeniería'];
  final d = res['data'] as Map<String, dynamic>?;
  final s = d?['sectores'] as List?;
  if (s == null || s.isEmpty) return ['Producción', 'Diseño', 'Comercial', 'Calidad', 'Ingeniería'];
  return List<String>.from(s.map((e) => e.toString()));
}

Future<Map<String, dynamic>> verificarDisponibilidad(String dataHora) async {
  final res = await _httpGet("$kScriptUrl?action=verificarDisponibilidad&dataHora=${Uri.encodeComponent(dataHora)}");
  if (res['success'] != true) return {'ok': false, 'disponible': true};
  final d = res['data'] as Map<String, dynamic>? ?? {};
  return {
    'ok': true,
    'disponible': d['disponible'] == true,
    'ocupaciones': d['ocupaciones'] ?? 0,
    'limite': d['limite'] ?? 4,
  };
}

Future<Map<String, int>> fetchOcupacaoBrigadas(String sector) async {
  final res = await _httpGet("$kScriptUrl?action=getOcupacaoBrigadas&sector=${Uri.encodeComponent(sector)}");
  if (res['success'] != true) return {};
  final d = res['data'] as Map<String, dynamic>?;
  final occ = d?['ocupacoes'] as Map<String, dynamic>?;
  if (occ == null) return {};
  return occ.map((k, v) => MapEntry(k, (v as num).toInt()));
}

void showOfflineDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sin conexión'),
      content: const Text('No hay señal. Por favor, intente enviar nuevamente cuando tenga cobertura.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
      ],
    ),
  );
}

void main() {
  runApp(const GestaoDuarteApp());
}

class GestaoDuarteApp extends StatefulWidget {
  const GestaoDuarteApp({super.key});

  @override
  State<GestaoDuarteApp> createState() => _GestaoDuarteAppState();
}

class _GestaoDuarteAppState extends State<GestaoDuarteApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Autopista Duarte',

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5631),
          primary: const Color(0xFF1E5631),
          secondary: const Color(0xFF4C9A2A),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E5631),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C9A2A),
          brightness: Brightness.dark,
          primary: const Color(0xFF4C9A2A),
          secondary: const Color(0xFF1E5631),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E5631),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      themeMode: _themeMode,
      home: TelaLogin(themeMode: _themeMode, onSetThemeMode: _setThemeMode),
    );
  }
}

class TelaLogin extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSetThemeMode;

  const TelaLogin({super.key, required this.themeMode, required this.onSetThemeMode});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // CONFIGURAÇÃO DA API (sem espaços extras, termina em /exec)
  final String _scriptUrl = "https://script.google.com/macros/s/AKfycbxaMMdfTsEV_gUd0Bg2l5D666FqUVEn5wynNyT_Cdt_iY4mg0zxbtzfFVlAeb87IzfqsQ/exec";
  
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // FUNÇÃO DE LOGIN VIA GOOGLE SHEETS
  Future<void> _realizarLogin() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _mostrarMensagem("Por favor, ingrese su correo", Colors.orange);
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      _mostrarMensagem("Por favor, ingrese su contraseña", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String email = _emailController.text.trim();
      final String senha = _passwordController.text.trim();
      final url = "${_scriptUrl.trim()}?action=login&email=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(senha)}";
      final res = await _httpGet(url);
      Map<String, dynamic>? usuario;
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null && data['usuario'] != null) {
        usuario = Map<String, dynamic>.from(data['usuario'] as Map);
      }
      if (usuario != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TelaHome(usuario: usuario!, themeMode: widget.themeMode, onSetThemeMode: widget.onSetThemeMode),
          ),
        );
      } else if (usuario == null) {
        final msg = (res['message'] ?? '').toString();
        _mostrarMensagem(msg.isNotEmpty ? msg : "Usuario no encontrado", Colors.red);
      }
    } catch (e, st) {
      debugPrint('Login error: $e\n$st');
      _mostrarMensagem("Error de conexión. Verifique su internet.", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _mostrarMensagem(String texto, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : Colors.white;

    return Scaffold(
      body: Stack(
        children: [
          // 1. IMAGEM DE FUNDO
          Positioned.fill(
            child: Image.asset(
              'assets/backgrounds/background1.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[800]),
            ),
          ),

          // 2. MÁSCARA DE LEGIBILIDADE
          Positioned.fill(
            child: Container(
              color: isDark ? Colors.black.withOpacity(0.75) : Colors.black.withOpacity(0.45),
            ),
          ),

          // 3. CONTEÚDO CENTRAL
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // LOGO
                  Image.asset(
                    'assets/logos_empresas/logo.png',
                    height: 100,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Logo error: $error');
                      return Image.asset(
                        'assets/logo.png',
                        height: 100,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.engineering, size: 80, color: Colors.white),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // TÍTULO
                  const Text(
                    'Iniciar Sesión',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // CAMPO E-MAIL
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Correo electrónico', style: TextStyle(color: labelColor, fontSize: 14)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'ejemplo@empresa.com',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.95),
                      prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[600], size: 22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // CAMPO CONTRASEÑA
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Contraseña', style: TextStyle(color: labelColor, fontSize: 14)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '••••••••••',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.95),
                      prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600], size: 22),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[600], size: 22),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // BOTÃO ACCEDER
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _realizarLogin,
                      child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('ACCEDER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // LINKS ADICIONAIS
                  TextButton(
                    onPressed: () {},
                    child: const Text('¿Olvidaste tu contraseña?', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Crear nueva cuenta', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TelaHome extends StatelessWidget {
  final Map<String, dynamic> usuario;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSetThemeMode;

  const TelaHome({super.key, required this.usuario, required this.themeMode, required this.onSetThemeMode});

  static const Color _corBotaoSector = Color(0xFF1E5631);
  static const Color _verdeEscuro = Color(0xFF1E5631);
  static const Color _verdeMedio = Color(0xFF4C9A2A);
  static const Color _cinzaEscuro = Color(0xFF424242);

  @override
  Widget build(BuildContext context) {
    final sectores = <Map<String, dynamic>>[
      {'nombre': 'SALA TÉCNICA', 'icon': Icons.engineering_rounded},
      {'nombre': 'TOPOGRAFÍA', 'icon': Icons.terrain},
      {'nombre': 'CALIDAD', 'icon': Icons.checklist_rounded},
      {'nombre': 'PLANIFICACIÓN', 'icon': Icons.architecture_rounded},
    ];
    final email = (usuario['Email'] ?? usuario['email'] ?? usuario['Correo'] ?? usuario['Nombre'] ?? '').toString();
    final perfil = usuario['Perfil'] ?? usuario['perfil'] ?? usuario['Función'] ?? 'Usuario';
    final empresa = usuario['Empresa'] ?? usuario['Area'] ?? usuario['area'] ?? 'Autopista Duarte';
    final proyecto = usuario['Proyecto'] ?? 'Autopista Duarte';

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Stack(
        children: [
          // Imagem de fundo (grúas)
          Positioned.fill(
            child: Image.asset(
              'assets/backgrounds/background1.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[900]),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.black.withOpacity(0.8),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header: perfil do usuário (paleta verde, cinza, branco)
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cinzaEscuro.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[600]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _verdeEscuro,
                        child: Icon(Icons.person, color: Colors.white, size: 34),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email.isNotEmpty ? email : (usuario['Nombre'] ?? '').toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Función: $perfil', style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                            Text('Empresa: $empresa', style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.logout_rounded, color: Colors.grey[400]),
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => TelaLogin(themeMode: themeMode, onSetThemeMode: onSetThemeMode)),
                            (route) => false,
                          );
                        },
                        tooltip: 'Cerrar sesión',
                      ),
                    ],
                  ),
                ),

                // Logo + chip de projeto
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Image.asset(
                          'assets/logos_empresas/logo.png',
                          height: 95,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Column(
                            children: [
                              Text('INGENIERIA', style: TextStyle(color: Colors.white, fontSize: 18)),
                              Text('ESTRELLA', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: _cinzaEscuro.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: _verdeMedio, width: 1),
                          ),
                          child: Text(proyecto, style: const TextStyle(color: Colors.white, fontSize: 15)),
                        ),
                        const SizedBox(height: 28),

                        // Botões de sectores (vertical, estilo píldora)
                        ...sectores.map((e) {
                          final nombreSector = e['nombre'] as String;
                          return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                print('Sector_Activo: $nombreSector');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TelaSubMenu(
                                      usuario: usuario,
                                      setorSelecionado: nombreSector,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                                decoration: BoxDecoration(
                                  color: _corBotaoSector,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(e['icon'] as IconData, color: Colors.white, size: 30),
                                    const SizedBox(width: 18),
                                    Text(
                                      e['nombre'] as String,
                                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                        }),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Barra de navegação inferior (paleta verde, cinza, branco)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _cinzaEscuro,
                    border: Border(top: BorderSide(color: Colors.grey[700]!)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavIcon(icon: Icons.dashboard_rounded, selected: true),
                      Icon(Icons.account_tree_rounded, color: Colors.grey[500], size: 26),
                      IconButton(
                        icon: Icon(Icons.settings_rounded, color: Colors.grey[500]),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TelaSettings(themeMode: themeMode, onSetThemeMode: onSetThemeMode),
                            ),
                          );
                        },
                        tooltip: 'Ajustes',
                      ),
                      Icon(Icons.help_outline_rounded, color: Colors.grey[500], size: 26),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- TelaSettings: Configurações (inclui modo claro/escuro) ---

class TelaSettings extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSetThemeMode;

  const TelaSettings({super.key, required this.themeMode, required this.onSetThemeMode});

  static const Color _verde = Color(0xFF1E5631);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[200];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Ajustes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: _verde,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modo oscuro',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          isDark ? 'Activado' : 'Desactivado',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch(
                  value: isDark,
                  onChanged: (v) => onSetThemeMode(v ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TelaSubMenu extends StatelessWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaSubMenu({super.key, required this.usuario, required this.setorSelecionado});

  static const Color _verdeEscuro = Color(0xFF1E5631);
  static const Color _cinzaEscuro = Color(0xFF424242);

  List<Map<String, dynamic>> _itensPorSetor() {
    return [
      {'nombre': 'AGENDA', 'icon': Icons.calendar_month, 'tela': 'agenda'},
      {'nombre': 'DEMANDAS', 'icon': Icons.list_alt, 'tela': 'demandas'},
      {'nombre': 'GESTIÓN', 'icon': Icons.assignment_turned_in, 'tela': 'gestion'},
      {'nombre': 'GRÁFICO', 'icon': Icons.bar_chart, 'tela': 'grafico'},
    ];
  }

  void _navegar(BuildContext context, String tela) {
    Widget destino;
    switch (tela) {
      case 'agenda': destino = TelaAgenda(usuario: usuario, setorSelecionado: setorSelecionado); break;
      case 'demandas': destino = TelaDemandas(usuario: usuario, setorSelecionado: setorSelecionado); break;
      case 'gestion': destino = TelaGestion(usuario: usuario, setorSelecionado: setorSelecionado); break;
      case 'grafico': destino = TelaGrafico(usuario: usuario, setorSelecionado: setorSelecionado); break;
      case 'mapa': destino = TelaMapa(usuario: usuario, setorSelecionado: setorSelecionado); break;
      default: return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => destino));
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itensPorSetor();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
      appBar: AppBar(
        title: Text(setorSelecionado, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _cinzaEscuro,
        foregroundColor: Colors.white,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
        ),
        itemCount: itens.length,
        itemBuilder: (context, index) {
          final item = itens[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _navegar(context, item['tela'] as String),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                decoration: BoxDecoration(
                  color: _verdeEscuro,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item['icon'] as IconData, color: Colors.white, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      item['nombre'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSector: () => Navigator.pop(context),
        onMenu: () => Navigator.pop(context),
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: usuario, setorSelecionado: setorSelecionado),
        )),
        onSolicitar: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TelaFormSolicitar(usuario: usuario, setorSelecionado: setorSelecionado),
          ));
        },
      ),
    );
  }
}

// --- TelaFormSolicitar: Formulário de Nova Demanda (conforme imagens) ---

class TelaFormSolicitar extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;
  final Map<String, dynamic>? demandaAnterior;
  final bool esReprogramacion;
  final String? localInicial;
  final String? coordenadaInicial;

  const TelaFormSolicitar({
    super.key,
    required this.usuario,
    required this.setorSelecionado,
    this.demandaAnterior,
    this.esReprogramacion = false,
    this.localInicial,
    this.coordenadaInicial,
  });

  @override
  State<TelaFormSolicitar> createState() => _TelaFormSolicitarState();
}

class _TelaFormSolicitarState extends State<TelaFormSolicitar> {
  static const Color _verde = Color(0xFF1E5631);
  static const Color _cinzaEscuro = Color(0xFF424242);

  String? _sectorSolicitante;
  final _solicitanteCtrl = TextEditingController();
  String? _sectorDestino;
  String? _tipoDemanda;
  String? _local;
  final _controllerLocal = TextEditingController();
  final _controllerCoordenadas = TextEditingController();
  bool _coordenadasFromMap = false;
  final _requerimientoCtrl = TextEditingController();
  final _fechaNecesariaCtrl = TextEditingController();
  final _horaInicioCtrl = TextEditingController();
  final _responsavelCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController();

  bool _enviando = false;
  bool _slotIndisponivel = false;
  List<String> _locais = ['Ponte Jarabacoa', 'Jaguey', 'Retorno San Francisco', 'Marginal San Francisco', 'Otro'];
  List<String> _sectores = ['Producción', 'Diseño', 'Comercial', 'Calidad', 'Ingeniería'];
  static const List<String> _sectoresDestino = ['Topografia', 'Sala Técnica', 'Calidad', 'Planificación'];
  static const List<String> _tiposDemanda = ['Apoyo', 'Aprob. Planos', 'Cubicacíon', 'Ensayos', 'Estudios', 'Información', 'Planos', 'Topografia'];
  static const String _opcaoMapa = 'Seleccionar en el Mapa';
  static const String _localMapa = 'Elegir en el mapa';

  @override
  void initState() {
    super.initState();
    _sectorSolicitante = widget.setorSelecionado;
    if (widget.localInicial != null && widget.localInicial!.isNotEmpty) {
      _controllerLocal.text = widget.localInicial!;
      _local = widget.localInicial;
      if (!_locais.contains(_local)) _locais = [..._locais, _local!];
    }
    if (widget.coordenadaInicial != null && widget.coordenadaInicial!.isNotEmpty) {
      _controllerCoordenadas.text = widget.coordenadaInicial!;
      _coordenadasFromMap = true;
    }
    _solicitanteCtrl.text = (widget.usuario['Nombre'] ?? widget.usuario['nombre'] ?? widget.usuario['Email'] ?? widget.usuario['email'] ?? '').toString();
    final now = _proximoHorarioLaboral(DateTime.now());
    _fechaNecesariaCtrl.text = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    _horaInicioCtrl.text = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';
    if (widget.demandaAnterior != null) {
      _requerimientoCtrl.text = (widget.demandaAnterior!['titulo'] ?? '').toString();
    }
    _carregarLocais();
    _carregarSectores();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarDisponibilidadeSlot());
  }

  Future<void> _carregarLocais() async {
    final locais = await fetchLocais();
    if (locais.isNotEmpty) {
      setState(() {
        _locais = [...locais, _opcaoMapa];
        if (_local != null && !_locais.contains(_local)) _locais = [..._locais, _local!];
      });
    } else if (_local != null && !_locais.contains(_local)) {
      setState(() => _locais = [..._locais, _local!]);
    }
  }

  Future<void> _carregarSectores() async {
    final sectores = await fetchSectores();
    if (sectores.isNotEmpty) {
      setState(() {
        _sectores = sectores;
        if (_sectorSolicitante != null && !_sectores.contains(_sectorSolicitante)) {
          _sectores = [..._sectores, _sectorSolicitante!];
        }
      });
    }
  }

  bool _isHorarioLaboral(DateTime dt) {
    final w = dt.weekday;
    final h = dt.hour;
    final m = dt.minute;
    final minDesdeMeiaNoite = h * 60 + m;
    if (w == DateTime.sunday) return false;
    if (w == DateTime.saturday) return minDesdeMeiaNoite >= 8 * 60 && minDesdeMeiaNoite < 12 * 60;
    return minDesdeMeiaNoite >= 8 * 60 && minDesdeMeiaNoite < 17 * 60;
  }

  DateTime _proximoHorarioLaboral(DateTime dt) {
    if (_isHorarioLaboral(dt)) return dt;
    if (dt.weekday == DateTime.sunday) return DateTime(dt.year, dt.month, dt.day + 1, 8, 0);
    if (dt.weekday == DateTime.saturday && (dt.hour >= 12 || dt.hour < 8)) return DateTime(dt.year, dt.month, dt.day + 1, 8, 0);
    if (dt.hour >= 17) return DateTime(dt.year, dt.month, dt.day + 1, 8, 0);
    return DateTime(dt.year, dt.month, dt.day, 8, 0);
  }

  bool _podeEnviar() {
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length != 3) return false;
      final dia = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      var hp = 8;
      var mp = 0;
      try {
        final h = _horaInicioCtrl.text.split(':');
        if (h.isNotEmpty) hp = int.parse(h[0]);
        if (h.length > 1) mp = int.parse(h[1].replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}
      final dt = DateTime(dia.year, dia.month, dia.day, hp, mp);
      return _isHorarioLaboral(dt) && !_slotIndisponivel;
    } catch (_) {
      return false;
    }
  }

  String _calcularHoraFin() {
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length != 3) return '';
      var dia = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      var hp = 8;
      var mp = 0;
      try {
        final h = _horaInicioCtrl.text.split(':');
        if (h.isNotEmpty) hp = int.parse(h[0]);
        if (h.length > 1) mp = int.parse(h[1].replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}
      var durMin = 60;
      try {
        final dur = _duracionCtrl.text.toLowerCase().trim();
        if (dur.contains('h')) {
          durMin = ((double.tryParse(dur.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.')) ?? 1) * 60).toInt();
        } else {
          durMin = int.tryParse(dur.replaceAll(RegExp(r'[^0-9]'), '')) ?? 60;
        }
      } catch (_) {}
      var fim = DateTime(dia.year, dia.month, dia.day, hp, mp).add(Duration(minutes: durMin.toInt()));
      while (!_isHorarioLaboral(DateTime(fim.year, fim.month, fim.day, fim.hour, fim.minute))) {
        if (fim.weekday == DateTime.sunday) fim = DateTime(fim.year, fim.month, fim.day + 1, 8, 0);
        else if (fim.weekday == DateTime.saturday && fim.hour >= 12) fim = DateTime(fim.year, fim.month, fim.day + 1, 8, 0);
        else if (fim.hour >= 17) fim = DateTime(fim.year, fim.month, fim.day + 1, 8, 0);
        else fim = DateTime(fim.year, fim.month, fim.day, 8, 0);
      }
      return '${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}:00';
    } catch (_) {
      return '';
    }
  }

  Future<void> _verificarDisponibilidadeSlot() async {
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length != 3) return;
      final dia = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      var hp = 8;
      var mp = 0;
      try {
        final h = _horaInicioCtrl.text.split(':');
        if (h.isNotEmpty) hp = int.parse(h[0]);
        if (h.length > 1) mp = int.parse(h[1].replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}
      final iso = DateTime(dia.year, dia.month, dia.day, hp, mp).toIso8601String();
      final res = await verificarDisponibilidad(iso);
      if (mounted) setState(() => _slotIndisponivel = res['ok'] == true && res['disponible'] == false);
    } catch (_) {
      if (mounted) setState(() => _slotIndisponivel = false);
    }
  }

  @override
  void dispose() {
    _solicitanteCtrl.dispose();
    _controllerLocal.dispose();
    _controllerCoordenadas.dispose();
    _requerimientoCtrl.dispose();
    _fechaNecesariaCtrl.dispose();
    _horaInicioCtrl.dispose();
    _responsavelCtrl.dispose();
    _duracionCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarData() async {
    var inicial = DateTime.now();
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length == 3) inicial = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {}
    final d = await showDatePicker(context: context, initialDate: inicial, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (d != null) {
      _fechaNecesariaCtrl.text = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      _ajustarHoraLaboral();
    }
  }

  void _ajustarHoraLaboral() {
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length != 3) return;
      final dia = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      var hp = 8;
      var mp = 0;
      try {
        final h = _horaInicioCtrl.text.split(':');
        if (h.isNotEmpty) hp = int.parse(h[0]);
        if (h.length > 1) mp = int.parse(h[1].replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}
      var dt = DateTime(dia.year, dia.month, dia.day, hp, mp);
      if (!_isHorarioLaboral(dt)) dt = _proximoHorarioLaboral(dt);
      _horaInicioCtrl.text = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';
      _verificarDisponibilidadeSlot();
    } catch (_) {}
  }

  Future<void> _selecionarHora() async {
    var hp = 8;
    var mp = 0;
    try {
      final h = _horaInicioCtrl.text.split(':');
      if (h.isNotEmpty) hp = int.parse(h[0]).clamp(0, 23);
      if (h.length > 1) mp = int.parse(h[1].replaceAll(RegExp(r'[^0-9]'), '')).clamp(0, 59);
    } catch (_) {}
    DateTime dia = DateTime.now();
    try {
      final p = _fechaNecesariaCtrl.text.split('/');
      if (p.length == 3) dia = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {}
    TimeOfDay initial = TimeOfDay(hour: hp, minute: mp);
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) {
      var dt = DateTime(dia.year, dia.month, dia.day, t.hour, t.minute);
      if (!_isHorarioLaboral(dt)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Horario fuera del expediente: Lun-Vie 08:00-17:00, Sáb 08:00-12:00')));
        dt = _proximoHorarioLaboral(dt);
      }
      _horaInicioCtrl.text = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';
      _verificarDisponibilidadeSlot();
    }
  }

  Future<void> _abrirMapaParaCoordenadas() async {
    final coords = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => TelaMapa(
        usuario: widget.usuario,
        setorSelecionado: widget.setorSelecionado,
        modoSelecao: true,
      ),
    ));
    if (coords != null && mounted) {
      _controllerCoordenadas.text = coords;
      setState(() => _coordenadasFromMap = true);
    }
  }

  void _cancelar() => Navigator.pop(context);

  Future<void> _enviar() async {
    if ((_sectorSolicitante ?? '').isEmpty || _solicitanteCtrl.text.trim().isEmpty ||
        _requerimientoCtrl.text.trim().isEmpty || _fechaNecesariaCtrl.text.trim().isEmpty || _horaInicioCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complete los campos obligatorios')));
      return;
    }
    if (!_podeEnviar()) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Horario no válido'),
          content: Text(_slotIndisponivel
              ? 'Horario NO DISPONIBLE (4 brigadas ocupadas en este slot).'
              : 'Hora Necesaria fuera del expediente. Permitido: Lun-Vie 08:00-17:00 o Sáb 08:00-12:00.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    final dados = <String, dynamic>{
      'sectorSolicitante': _sectorSolicitante ?? '',
      'solicitante': _solicitanteCtrl.text.trim(),
      'sectorDestino': _sectorDestino ?? '',
      'tipoDemanda': _tipoDemanda ?? '',
      'local': (_local == _opcaoMapa || _local == _localMapa) ? '' : (_local ?? ''),
      'coordenadas': _controllerCoordenadas.text.trim(),
      'requerimiento': _requerimientoCtrl.text.trim(),
      'fechaNecesaria': _fechaNecesariaCtrl.text.trim(),
      'horaInicio': _horaInicioCtrl.text.trim(),
      'status': widget.esReprogramacion ? '' : 'No Programada',
      'horaFin': _calcularHoraFin(),
      'responsable': isPerfilGestion(widget.usuario) ? _responsavelCtrl.text.trim() : '',
      'duracion': isPerfilGestion(widget.usuario) ? _duracionCtrl.text.trim() : '',
    };
    if (widget.esReprogramacion && widget.demandaAnterior != null) {
      dados['idDemandaAnterior'] = (widget.demandaAnterior!['id'] ?? widget.demandaAnterior!['index'] ?? '').toString();
    }
    Map<String, dynamic> res = {'ok': false};
    try {
      res = widget.esReprogramacion
          ? await crearDemandaReprogramada(dados)
          : await crearDemanda(dados);
    } catch (_) {}
    setState(() => _enviando = false);
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demanda enviada correctamente'), backgroundColor: _verde));
      Navigator.pop(context);
    } else {
      final msg = (res['message'] ?? '').toString();
      if (msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      } else {
        showOfflineDialog(context);
      }
    }
  }

  Widget _campo(String label, TextEditingController ctrl, {bool obrigatorio = true, bool multiline = false, VoidCallback? onTap, IconData? suffixIconData, bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        readOnly: readOnly || onTap != null,
        onTap: onTap,
        maxLines: multiline ? 4 : 1,
        decoration: InputDecoration(
          labelText: label + (obrigatorio ? ' *' : ''),
          labelStyle: const TextStyle(color: Colors.white70),
          suffixIcon: onTap != null ? Icon(suffixIconData ?? Icons.calendar_today, color: Colors.grey[500], size: 20) : null,
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _verde, width: 1.5)),
          filled: true,
          fillColor: _cinzaEscuro.withOpacity(0.6),
        ),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  bool get _localReadOnly => _local == _localMapa;

  Widget _campoCoordenadas() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _controllerCoordenadas,
              readOnly: _coordenadasFromMap,
              decoration: InputDecoration(
                labelText: 'Coordenadas',
                labelStyle: const TextStyle(color: Colors.white70),
                suffixIcon: _coordenadasFromMap ? Icon(Icons.check_circle, color: _verde, size: 20) : null,
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
                focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _verde, width: 1.5)),
                filled: true,
                fillColor: _cinzaEscuro.withOpacity(0.6),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                final coords = await Navigator.push<String>(context, MaterialPageRoute(
                  builder: (_) => TelaMapa(
                    usuario: widget.usuario,
                    setorSelecionado: widget.setorSelecionado,
                    modoSelecao: true,
                  ),
                ));
                if (coords != null && mounted) {
                  _controllerCoordenadas.text = coords;
                  setState(() => _coordenadasFromMap = true);
                }
              },
              icon: Icon(Icons.place, size: 18, color: Colors.grey[600]),
              label: Text('Seleccionar en Mapa', style: TextStyle(color: Colors.grey[600])),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[600],
                side: BorderSide(color: Colors.grey[600]!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownLocal() {
    if (_localReadOnly) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: _controllerLocal,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Local',
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _verde, width: 1.5)),
            filled: true,
            fillColor: _cinzaEscuro.withOpacity(0.6),
          ),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: _locais.contains(_local) ? _local : null,
        onChanged: (v) async {
          if (v == _opcaoMapa) {
            await _abrirMapaParaCoordenadas();
            setState(() => _local = v);
          } else {
            setState(() => _local = v);
          }
        },
        decoration: InputDecoration(
          labelText: 'Local',
          labelStyle: const TextStyle(color: Colors.white70),
          suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _verde, width: 1.5)),
          filled: true,
          fillColor: _cinzaEscuro.withOpacity(0.6),
        ),
        dropdownColor: Colors.grey[800],
        items: _locais.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: Colors.white)))).toList(),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<String> opcoes, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: opcoes.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: label + ' *',
          labelStyle: const TextStyle(color: Colors.white70),
          suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: _verde, width: 1.5)),
          filled: true,
          fillColor: _cinzaEscuro.withOpacity(0.6),
        ),
        dropdownColor: Colors.grey[800],
        items: opcoes.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: Colors.white)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeGestao = isPerfilGestion(widget.usuario);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _cancelar),
      ),
      backgroundColor: Colors.grey[900],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropdown('Sector Solicitante', _sectorSolicitante, _sectores, (v) => setState(() => _sectorSolicitante = v)),
            _campo('Solicitante', _solicitanteCtrl),
            _dropdown('Sector de Destino', _sectorDestino, _sectoresDestino, (v) => setState(() => _sectorDestino = v)),
            _dropdown('Tipo de Demanda', _tipoDemanda, _tiposDemanda, (v) => setState(() => _tipoDemanda = v)),
            _dropdownLocal(),
            _campoCoordenadas(),
            _campo('Requerimiento', _requerimientoCtrl, multiline: true),
            _campo('Fecha Necesaria', _fechaNecesariaCtrl, onTap: _selecionarData, suffixIconData: Icons.calendar_today),
            _campo('Hora Inicio', _horaInicioCtrl, onTap: _selecionarHora, suffixIconData: Icons.access_time),
            if (podeGestao) ...[
              _campo('Responsable', _responsavelCtrl, obrigatorio: false),
              _campo('Duración (h)', _duracionCtrl, obrigatorio: false),
            ],
            if (!_podeEnviar())
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _slotIndisponivel ? 'NO DISPONIBLE: 4 brigadas ocupadas en este horario.' : 'Horario fuera del expediente: Lun-Vie 08:00-17:00, Sáb 08:00-12:00. Domingos no permitidos.',
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _enviando ? null : _cancelar, child: const Text('Cancelar', style: TextStyle(color: Colors.white))),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: (_enviando || !_podeEnviar()) ? null : _enviar,
                  style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey),
                  child: _enviando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enviar'),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSolicitar: () {},
        onSector: () => Navigator.pop(context),
        onMenu: () => Navigator.pop(context),
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
        )),
      ),
    );
  }
}

// --- Barra inferior compartilhada (SECTOR, MENU, Solicitar) ---

class _BarraInferiorSubTela extends StatelessWidget {
  final VoidCallback? onSolicitar;
  final VoidCallback? onSector;
  final VoidCallback? onMenu;
  final VoidCallback? onMapa;

  const _BarraInferiorSubTela({this.onSolicitar, this.onMenu, this.onSector, this.onMapa});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: const Color(0xFF1E5631),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ItemBarra(icon: Icons.account_tree, label: 'SECTOR', onTap: onSector ?? () => Navigator.pop(context)),
          _ItemBarra(icon: Icons.menu, label: 'MENU', onTap: onMenu ?? () => Navigator.pop(context)),
          _ItemBarra(icon: Icons.map, label: 'MAPA', onTap: onMapa ?? () {}),
          _ItemBarra(icon: Icons.add_circle_outline, label: 'Solicitar', onTap: onSolicitar ?? () {}),
        ],
      ),
    );
  }
}

class _ItemBarra extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ItemBarra({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 28),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ]),
  );
}

AppBar _appBarComBadge(BuildContext context, String titulo, {VoidCallback? onSearch, VoidCallback? onRefresh, int badgeCount = 3, bool showRefreshBadge = true}) {
  return AppBar(
    title: Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    backgroundColor: const Color(0xFF1E5631),
    foregroundColor: Colors.white,
    actions: [
      IconButton(icon: const Icon(Icons.search), onPressed: onSearch ?? () {}),
      if (showRefreshBadge)
        Stack(
          children: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh ?? () {}),
            if (badgeCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                  child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
          ],
        ),
    ],
  );
}

// --- TelaDetalleDemanda: Detalhes de uma demanda ---

class TelaDetalleDemanda extends StatelessWidget {
  final Map<String, dynamic> demanda;
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaDetalleDemanda({
    super.key,
    required this.demanda,
    required this.usuario,
    required this.setorSelecionado,
  });

  static const Color _verde = Color(0xFF1E5631);

  Future<void> _confirmarCancelar(BuildContext context) async {
    final d = demanda;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Cancelar demanda'),
      content: Text('¿Estás seguro que deseas cancelar "${(d['titulo'] ?? d['local'] ?? '').toString()}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
      ],
    ));
    if (ok != true) return;
    final dados = <String, dynamic>{
      'sectorSolicitante': d['sector'] ?? d['setor'] ?? setorSelecionado,
      'solicitante': d['solicitante'] ?? '',
      'requerimiento': 'CANCELADA: ${d['titulo'] ?? d['local'] ?? ''}',
      'idDemandaAnterior': (d['id'] ?? d['index'] ?? '').toString(),
    };
    final success = await crearDemandaCancelada(dados);
    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demanda cancelada'), backgroundColor: _verde));
      Navigator.pop(context);
    } else {
      showOfflineDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = demanda;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DETALLES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: const [],
      ),
      backgroundColor: Colors.grey[900],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filaDetalle('Local', (d['local'] ?? '').toString()),
            _filaDetalle('Sector Solicitante', (d['setor'] ?? d['sector'] ?? '').toString()),
            _filaDetalle('Solicitante', (d['solicitanteNome'] ?? d['solicitante'] ?? '').toString()),
            _filaDetalle('Tipo de Demanda', (d['tipoDemanda'] ?? '').toString()),
            _filaDetalle('Requerimiento', (d['requerimiento'] ?? d['titulo'] ?? '').toString()),
            _filaDetalleFecha('Fecha Necesaria', (d['fechaNecesaria'] ?? d['data'] ?? '').toString()),
            _filaDetalle('Hora Inicio', (d['horaInicio'] ?? d['hora'] ?? '').toString()),
            _filaDetalle('Estatus Actual', (d['status'] ?? 'Pendiente').toString()),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => TelaFormSolicitar(
                          usuario: usuario,
                          setorSelecionado: setorSelecionado,
                          demandaAnterior: demanda,
                          esReprogramacion: true,
                        ),
                      )).then((_) => Navigator.pop(context));
                    },
                    icon: const Icon(Icons.edit_calendar, size: 18, color: Colors.amber),
                    label: const Text('Reprogramar', style: TextStyle(color: Colors.amber)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.amber, side: const BorderSide(color: Colors.amber)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmarCancelar(context),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSector: () => Navigator.popUntil(context, (r) => r.isFirst),
        onMenu: () => Navigator.pop(context),
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: usuario, setorSelecionado: setorSelecionado),
        )),
        onSolicitar: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaFormSolicitar(usuario: usuario, setorSelecionado: setorSelecionado),
        )),
      ),
    );
  }

  Widget _filaDetalle(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _filaDetalleFecha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue[400], size: 18),
                const SizedBox(width: 8),
                Text(valor, style: TextStyle(color: Colors.blue[400], fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- TelaDemandas: Lista de Demandas ---

class TelaDemandas extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaDemandas({super.key, required this.usuario, required this.setorSelecionado});

  @override
  State<TelaDemandas> createState() => _TelaDemandasState();
}

class _TelaDemandasState extends State<TelaDemandas> {
  static const Color _verde = Color(0xFF1E5631);
  String? _filtroEstatus;
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();

  late Future<List<Map<String, dynamic>>> _futureDemandas;

  @override
  void initState() {
    super.initState();
    _futureDemandas = _fetchDemandas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchDemandas() {
    final perfil = (widget.usuario['Perfil'] ?? widget.usuario['perfil'] ?? widget.usuario['Función'] ?? '').toString();
    final params = parametrosFetchPorPerfil(widget.usuario);
    return fetchDemandas(widget.setorSelecionado, email: params.email, perfil: perfil, responsable: params.responsable);
  }

  void _abrirFormSolicitar(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TelaFormSolicitar(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
    )).then((_) => setState(() {}));
  }

  List<Map<String, dynamic>> _filtrarPorTexto(List<Map<String, dynamic>> lista, String query) {
    if (query.trim().isEmpty) return lista;
    final q = query.trim().toLowerCase();
    return lista.where((d) {
      final campos = [
        (d['local'] ?? '').toString(),
        (d['titulo'] ?? '').toString(),
        (d['requerimiento'] ?? '').toString(),
        (d['tipoDemanda'] ?? '').toString(),
        (d['solicitante'] ?? d['solicitanteNome'] ?? '').toString(),
        (d['setor'] ?? d['sector'] ?? '').toString(),
      ];
      return campos.any((c) => c.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final opcoesEstatus = ['Todos', 'No Programada', 'Programada', 'Resuelta', 'Cancelada'];
    return Scaffold(
      appBar: _appBarComBadge(
        context,
        'DEMANDAS',
        onSearch: () => setState(() {
          _searchVisible = !_searchVisible;
          if (!_searchVisible) _searchController.clear();
        }),
        showRefreshBadge: false,
      ),
      backgroundColor: Colors.grey[900],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureDemandas,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _verde));
          }
          var demandas = List<Map<String, dynamic>>.from((snap.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
          demandas = _filtrarPorTexto(demandas, _searchController.text);
          if (_filtroEstatus != null && _filtroEstatus != 'Todos') {
            final f = _filtroEstatus!.toLowerCase();
            demandas = demandas.where((d) {
              final st = (d['status'] ?? '').toString().toLowerCase();
              return (f == 'no programada' && st.contains('no programada')) ||
                  (f == 'programada' && (st.contains('programada') && !st.contains('no') || st.contains('pendiente'))) ||
                  (f == 'resuelta' && st.contains('resuel')) ||
                  (f == 'cancelada' && st.contains('cancel'));
            }).toList();
          }
          if (demandas.isEmpty) {
            return Column(
              children: [
                if (_searchVisible) _searchBarWidget(),
                _filtroEstatusWidget(opcoesEstatus),
                Expanded(child: Center(child: Text('Sin demandas', style: TextStyle(color: Colors.grey[400])))),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchVisible) _searchBarWidget(),
              _filtroEstatusWidget(opcoesEstatus),
              Expanded(
                child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: demandas.length,
            itemBuilder: (context, i) {
              final d = demandas[i];
              final status = (d['status'] ?? 'Pendiente').toString();
              final corBadge = status.toLowerCase().contains('resolv') ? Colors.blue
                  : status.toLowerCase().contains('aberto') || status.toLowerCase().contains('abiert') ? Colors.orange
                  : Colors.red;
              return InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TelaDetalleDemanda(
                    demanda: d,
                    usuario: widget.usuario,
                    setorSelecionado: widget.setorSelecionado,
                  ),
                )).then((_) => setState(() {})),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((d['local'] ?? d['titulo'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text((d['tipoDemanda'] ?? d['setor'] ?? '').toString(), style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: corBadge, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Text((d['data'] ?? '').toString(), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormSolicitar(context),
        child: const Icon(Icons.add),
        backgroundColor: Colors.grey,
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSolicitar: () => _abrirFormSolicitar(context),
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
        )),
      ),
    );
  }

  Widget _searchBarWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey[850],
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey[400], size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por local, tipo, solicitante...',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              autofocus: true,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => setState(() {
              _searchVisible = false;
              _searchController.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _filtroEstatusWidget(List<String> opcoes) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: opcoes.map((e) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(e, style: TextStyle(color: (_filtroEstatus == e || (_filtroEstatus == null && e == 'Todos')) ? Colors.white : null)),
            selected: _filtroEstatus == e || (_filtroEstatus == null && e == 'Todos'),
            onSelected: (v) => setState(() => _filtroEstatus = v ? (e == 'Todos' ? null : e) : null),
            selectedColor: _verde.withOpacity(0.7),
          ),
        )).toList(),
      ),
    );
  }
}

// --- TelaGestion: Fila Limpa (Responsável vazio) - Regra 9.3 ---

class TelaGestion extends StatelessWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaGestion({super.key, required this.usuario, required this.setorSelecionado});

  static const Color _verde = Color(0xFF1E5631);

  void _mostrarFormProgramar(BuildContext context, Map<String, dynamic> item) {
    final respController = TextEditingController();
    final durController = TextEditingController();
    final dataController = TextEditingController();
    final horaController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Programar: ${item['tema'] ?? item['titulo'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: respController, decoration: const InputDecoration(labelText: 'Responsable')),
              TextField(controller: durController, decoration: const InputDecoration(labelText: 'Duración Estimada')),
              TextField(controller: dataController, decoration: const InputDecoration(labelText: 'Fecha')),
              TextField(controller: horaController, decoration: const InputDecoration(labelText: 'Hora')),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: _verde),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestión - $setorSelecionado'),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: () {
          final perfil = (usuario['Perfil'] ?? usuario['perfil'] ?? usuario['Función'] ?? '').toString();
          final params = parametrosFetchPorPerfil(usuario);
          return fetchDemandasGestion(setorSelecionado, perfil: perfil, email: params.email, responsable: params.responsable);
        }(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _verde));
          }
          final demandas = snap.data ?? [];
          if (demandas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('Cola vacía', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
                  Text('Ninguna demanda pendiente de programación', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: demandas.length,
            itemBuilder: (context, i) {
              final d = demandas[i];
              final tema = (d['tema'] ?? d['titulo'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: Text(tema, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500))),
                      ElevatedButton.icon(
                        onPressed: () => _mostrarFormProgramar(context, d),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Programar'),
                        style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSolicitar: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TelaFormSolicitar(usuario: usuario, setorSelecionado: setorSelecionado),
          ));
        },
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: usuario, setorSelecionado: setorSelecionado),
        )),
      ),
    );
  }
}

// --- TelaAgenda: Visão do Executor (Grade de horários + tarefas) ---

class TelaAgenda extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaAgenda({super.key, required this.usuario, required this.setorSelecionado});

  @override
  State<TelaAgenda> createState() => _TelaAgendaState();
}

class _TelaAgendaState extends State<TelaAgenda> {
  static const Color _verde = Color(0xFF1E5631);
  static const Color _cinzaDisponivel = Color(0xFF6B6B6B);
  DateTime _diaSelecionado = DateTime.now();

  bool get _isTopografia => widget.setorSelecionado.toUpperCase().contains('TOPOGRAF');

  List<Map<String, dynamic>> _gerarSlotsDoDia(Map<String, int> ocupacao, DateTime dia) {
    final slots = <Map<String, dynamic>>[];
    final dataStr = '${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}/${dia.year}';
    final maxH = dia.weekday == DateTime.saturday ? 12 : 17;
    for (var h = 8; h < maxH; h++) {
      final horaStr = '${h.toString().padLeft(2, '0')}:00';
      final key = '$dataStr|$horaStr';
      slots.add({'data': dataStr, 'hora': horaStr, 'ocupacao': ocupacao[key] ?? 0});
    }
    return slots;
  }

  Map<String, List<Map<String, dynamic>>> _agruparPorData(List<Map<String, dynamic>> demandas, String setorSelecionado) {
    final porData = <String, List<Map<String, dynamic>>>{};
    for (final d in demandas) {
      final data = (d['data'] ?? '').toString();
      if (!porData.containsKey(data)) porData[data] = [];
      porData[data]!.add(d);
    }
    final chaves = porData.keys.toList()..sort((a, b) {
      try {
        final pa = a.split('/'); final da = DateTime(int.parse(pa[2]), int.parse(pa[1]), int.parse(pa[0]));
        final pb = b.split('/'); final db = DateTime(int.parse(pb[2]), int.parse(pb[1]), int.parse(pb[0]));
        return da.compareTo(db);
      } catch (_) { return a.compareTo(b); }
    });
    return Map.fromEntries(chaves.map((k) => MapEntry(k, porData[k]!)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBarComBadge(context, 'AGENDA'),
      backgroundColor: Colors.grey[900],
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          () {
            final perfil = (widget.usuario['Perfil'] ?? widget.usuario['perfil'] ?? widget.usuario['Función'] ?? '').toString();
            final params = parametrosFetchPorPerfil(widget.usuario);
            return fetchDemandasAgenda(widget.setorSelecionado, email: params.email, perfil: perfil, responsable: params.responsable);
          }(),
          _isTopografia ? fetchOcupacaoBrigadas(widget.setorSelecionado) : Future.value(<String, int>{}),
        ]),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _verde));
          }
          final results = snap.data ?? [<Map<String, dynamic>>[], {}];
          final demandas = (results.isNotEmpty && results[0] is List) ? List<Map<String, dynamic>>.from((results[0] as List).map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[];
          final occRaw = results.length > 1 ? results[1] : <String, int>{};
          final ocupacao = occRaw is Map ? Map<String, int>.from(occRaw.map((k, v) => MapEntry(k.toString(), (v is int ? v : (v as num).toInt())))) : <String, int>{};
          if (_isTopografia) {
            final slots = _gerarSlotsDoDia(ocupacao, _diaSelecionado);
            final dataStr = '${_diaSelecionado.day.toString().padLeft(2, '0')}/${_diaSelecionado.month.toString().padLeft(2, '0')}/${_diaSelecionado.year}';
            final tarefasDoDia = demandas.where((d) => (d['data'] ?? '').toString() == dataStr).toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Día:', style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: _diaSelecionado, firstDate: DateTime(2020), lastDate: DateTime(2030));
                          if (d != null) setState(() => _diaSelecionado = d);
                        },
                        child: Text(dataStr, style: const TextStyle(color: Colors.red, fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Cuadrícula de horarios (Semáforo Brigadas)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('0-3 brigadas: Disponible (Verde)  |  4 brigadas: NO DISPONIBLE - Límite alcanzado (Rojo)', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                  const SizedBox(height: 12),
                  ...slots.map((s) {
                    final occ = s['ocupacao'] as int;
                    final disp = occ < 4;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: disp ? _cinzaDisponivel : Colors.red.withOpacity(0.5),
                      child: ListTile(
                        title: Text('${s['hora']} - ${s['ocupacao']}/4 brigadas', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        trailing: Text(disp ? 'Disponible' : 'NO DISPONIBLE - Límite alcanzado', style: TextStyle(color: disp ? Colors.white : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  const Text('Tareas del día', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...tarefasDoDia.map((d) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.grey[800],
                    child: ListTile(
                      title: Text((d['titulo'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: Text('${d['responsavel'] ?? ''} • ${d['hora'] ?? ''}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                    ),
                  )),
                  if (tarefasDoDia.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Ninguna tarea programada', style: TextStyle(color: Colors.grey[500]))),
                ],
              ),
            );
          }
          if (demandas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('Sin demandas programadas', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
                ],
              ),
            );
          }
          final porData = _agruparPorData(demandas, widget.setorSelecionado);
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: porData.length,
            itemBuilder: (context, i) {
              final data = porData.keys.elementAt(i);
              final lista = porData[data]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(width: 4, height: 20, color: _cinzaDisponivel),
                        const SizedBox(width: 8),
                        Text(data, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  ...lista.map((d) {
                    final h = (d['hora'] ?? '').toString();
                    final horaStr = h.length >= 5 ? h.substring(0, 5) : h;
                    final key = '$data|$horaStr';
                    final occ = _isTopografia ? (ocupacao[key] ?? 0) : 0;
                    final disp = occ < 4;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: disp ? Colors.grey[800] : Colors.red.withOpacity(0.2),
                      child: ListTile(
                        title: Text((d['titulo'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        subtitle: Text('Responsable: ${(d['responsavel'] ?? '').toString()}${(d['hora'] ?? '').toString().isNotEmpty ? ' • ${d['hora']}' : ''}${_isTopografia ? ' • $occ/4 brigadas' : ''}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                        trailing: _isTopografia && !disp ? const Text('NO DISPONIBLE', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)) : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSolicitar: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TelaFormSolicitar(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
          ));
        },
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
        )),
      ),
    );
  }
}

// --- TelaGrafico: Carga de Trabalho por Responsáveis ---

enum _PeriodoGrafico { dia, semana, mes }

class TelaGrafico extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;

  const TelaGrafico({super.key, required this.usuario, required this.setorSelecionado});

  @override
  State<TelaGrafico> createState() => _TelaGraficoState();
}

class _TelaGraficoState extends State<TelaGrafico> {
  static const Color _verde = Color(0xFF1E5631);
  static const Color _verdeClaro = Color(0xFF5B9A4B);

  _PeriodoGrafico _periodo = _PeriodoGrafico.semana;

  bool _dataNoPeriodo(String? dataStr, _PeriodoGrafico periodo) {
    if (dataStr == null || dataStr.trim().isEmpty) return false;
    try {
      final parts = dataStr.trim().split('/');
      if (parts.length != 3) return false;
      final dia = int.tryParse(parts[0]) ?? 0;
      final mes = int.tryParse(parts[1]) ?? 0;
      final ano = int.tryParse(parts[2]) ?? 0;
      if (dia == 0 || mes == 0 || ano == 0) return false;
      final dt = DateTime(ano, mes, dia);
      final hoy = DateTime.now();
      switch (periodo) {
        case _PeriodoGrafico.dia:
          return dt.year == hoy.year && dt.month == hoy.month && dt.day == hoy.day;
        case _PeriodoGrafico.semana:
          final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
          final finSemana = inicioSemana.add(const Duration(days: 6));
          return !dt.isBefore(DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day)) &&
              !dt.isAfter(DateTime(finSemana.year, finSemana.month, finSemana.day));
        case _PeriodoGrafico.mes:
          return dt.year == hoy.year && dt.month == hoy.month;
      }
    } catch (_) {
      return false;
    }
  }

  double _parseDuracion(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    final s = val.toString().trim().replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  List<Map<String, dynamic>> _processarCargaTrabalho(List<Map<String, dynamic>> demandas) {
    final mapa = <String, Map<String, dynamic>>{};
    for (final d in demandas) {
      final resp = (d['responsavel'] ?? d['responsable'] ?? '').toString().trim();
      if (resp.isEmpty) continue;
      if (!_dataNoPeriodo((d['fechaNecesaria'] ?? d['data'] ?? '').toString(), _periodo)) continue;
      final st = (d['status'] ?? '').toString().toLowerCase();
      if (st.contains('cancel')) continue;
      final horas = _parseDuracion(d['duracion']);
      if (!mapa.containsKey(resp)) {
        mapa[resp] = {'responsavel': resp, 'totalHoras': 0.0, 'qtdDemandas': 0};
      }
      mapa[resp]!['totalHoras'] = (mapa[resp]!['totalHoras'] as num) + horas;
      mapa[resp]!['qtdDemandas'] = (mapa[resp]!['qtdDemandas'] as int) + 1;
    }
    final lista = mapa.values.toList();
    lista.sort((a, b) => (b['totalHoras'] as num).compareTo(a['totalHoras'] as num));
    return lista;
  }

  String _abreviarNome(String nome, {int maxLen = 8}) {
    if (nome.length <= maxLen) return nome;
    return '${nome.substring(0, maxLen - 1)}.';
  }

  @override
  Widget build(BuildContext context) {
    final perfil = (widget.usuario['Perfil'] ?? widget.usuario['perfil'] ?? widget.usuario['Función'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carga de Trabajo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: () {
          final params = parametrosFetchPorPerfil(widget.usuario);
          return fetchDemandas(widget.setorSelecionado, perfil: perfil, email: params.email, responsable: params.responsable);
        }(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _verde));
          }
          final demandas = snap.data ?? [];
          final carga = _processarCargaTrabalho(demandas);
          final cargaTotalHoras = carga.fold<double>(0, (s, c) => s + ((c['totalHoras'] as num).toDouble()));
          final volumeTotal = carga.fold<int>(0, (s, c) => s + (c['qtdDemandas'] as int));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_PeriodoGrafico>(
                  segments: const [
                    ButtonSegment(value: _PeriodoGrafico.dia, label: Text('Día'), icon: Icon(Icons.today, size: 18)),
                    ButtonSegment(value: _PeriodoGrafico.semana, label: Text('Semana'), icon: Icon(Icons.date_range, size: 18)),
                    ButtonSegment(value: _PeriodoGrafico.mes, label: Text('Mes'), icon: Icon(Icons.calendar_month, size: 18)),
                  ],
                  selected: {_periodo},
                  onSelectionChanged: (Set<_PeriodoGrafico> sel) {
                    setState(() => _periodo = sel.first);
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? _verde : Colors.grey[800]),
                    foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Colors.grey[400]),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        color: Colors.grey[800],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Carga Total', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                              Text('${cargaTotalHoras.toStringAsFixed(1)} h', style: const TextStyle(color: _verde, fontSize: 22, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        color: Colors.grey[800],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Volumen', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                              Text('$volumeTotal ítems', style: const TextStyle(color: _verdeClaro, fontSize: 22, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (carga.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Sin demandas programadas en el período', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final maxHoras = carga.map((c) => (c['totalHoras'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
                      final maxQtd = carga.map((c) => (c['qtdDemandas'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
                      final maxY = (maxHoras > maxQtd ? maxHoras : maxQtd) * 1.2;
                      return SizedBox(
                        height: 320,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: maxY.clamp(1.0, double.infinity),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  if (groupIndex < 0 || groupIndex >= carga.length) return null;
                                  final c = carga[groupIndex];
                                  if (rodIndex == 0) {
                                    return BarTooltipItem('${(c['totalHoras'] as num).toStringAsFixed(1)} h', TextStyle(color: rod.color, fontWeight: FontWeight.bold));
                                  }
                                  return BarTooltipItem('${c['qtdDemandas']} ítems', TextStyle(color: rod.color, fontWeight: FontWeight.bold));
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (val, meta) {
                                    final i = val.toInt();
                                    if (i < 0 || i >= carga.length) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Transform.rotate(
                                        angle: -0.6,
                                        child: Text(_abreviarNome(carga[i]['responsavel'] as String), style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                                      ),
                                    );
                                  },
                                  reservedSize: 36,
                                  interval: 1,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                                  reservedSize: 28,
                                  interval: maxY / 5,
                                ),
                              ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[800]!, strokeWidth: 0.5)),
                        barGroups: [
                          for (int i = 0; i < carga.length; i++) ...[
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(toY: (carga[i]['totalHoras'] as num).toDouble(), color: _verde, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                                BarChartRodData(toY: (carga[i]['qtdDemandas'] as num).toDouble(), color: _verdeClaro, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                              ],
                              showingTooltipIndicators: [],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                    },
                  ),
                if (carga.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 12, height: 12, color: _verde),
                            const SizedBox(width: 6),
                            Text('Horas', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 12, height: 12, color: _verdeClaro),
                            const SizedBox(width: 6),
                            Text('Cantidad', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _BarraInferiorSubTela(
        onSolicitar: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TelaFormSolicitar(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
          ));
        },
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
        )),
      ),
    );
  }
}

// --- TelaMapa: Geolocalização das frentes de obra ---

class TelaMapa extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String setorSelecionado;
  final bool modoSelecao;

  const TelaMapa({super.key, required this.usuario, required this.setorSelecionado, this.modoSelecao = false});

  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  static const Color _verde = Color(0xFF1E5631);
  static const LatLng _centroObra = LatLng(19.4517, -70.6970);
  LatLng _posicaoCentral = _centroObra;
  bool _modoSatelite = false;
  GoogleMapController? _mapController;

  Future<void> _irParaLocalAtual() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final novaPos = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _posicaoCentral = novaPos);
      await _mapController?.animateCamera(CameraUpdate.newLatLng(novaPos));
    } catch (_) {}
  }

  void _onCameraMove(CameraPosition position) {
    _posicaoCentral = position.target;
  }

  void _onMapTap(LatLng position) async {
    setState(() => _posicaoCentral = position);
    await _mapController?.animateCamera(CameraUpdate.newLatLng(position));
  }

  void _confirmarLocal() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TelaFormSolicitar(
          usuario: widget.usuario,
          setorSelecionado: widget.setorSelecionado,
          localInicial: 'Elegir en el mapa',
          coordenadaInicial: '${_posicaoCentral.latitude}, ${_posicaoCentral.longitude}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modoSelecao ? 'Seleccionar Local en el Mapa' : 'MAPA'),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _modoSatelite = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_modoSatelite ? Colors.grey[700] : Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text('Mapa', style: TextStyle(color: !_modoSatelite ? Colors.white : Colors.grey[500]))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _modoSatelite = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _modoSatelite ? Colors.grey[700] : Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text('Satélite', style: TextStyle(color: _modoSatelite ? Colors.white : Colors.grey[500]))),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _posicaoCentral, zoom: 16),
                  onMapCreated: (c) {
                    _mapController = c;
                    _irParaLocalAtual();
                  },
                  onTap: _onMapTap,
                  onCameraMove: _onCameraMove,
                  mapType: _modoSatelite ? MapType.satellite : MapType.normal,
                  myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapToolbarEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 35),
                    child: IgnorePointer(
                      child: Icon(Icons.location_on, color: Colors.red, size: 50),
                    ),
                  ),
                ),
                  Positioned(
                  bottom: 20,
                  left: 20,
                  right: 60,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: ElevatedButton.icon(
                        onPressed: _confirmarLocal,
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('CONFIRMAR ESTE LOCAL', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _verde,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 8,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Toque el mapa para marcar o arrastre para posicionar el marcador. Luego confirme.',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.modoSelecao ? null : _BarraInferiorSubTela(
        onSolicitar: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TelaFormSolicitar(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
          ));
        },
        onMapa: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TelaMapa(usuario: widget.usuario, setorSelecionado: widget.setorSelecionado),
        )),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _NavIcon({required this.icon, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      color: selected ? const Color(0xFF4C9A2A) : Colors.grey[500],
      size: 28,
    );
  }
}