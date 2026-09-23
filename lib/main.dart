import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:signature/signature.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VirtusPrivacyApp());
}

class AppAdminConfig {
  static const String adminPassword = String.fromEnvironment(
    'APP_ADMIN_PASSWORD',
    defaultValue: '',
  );
}

class ModulesRepository {
  static const String _assetPath = 'assets/modules.json';
  static const String _localFileName = 'modules_runtime.json';
  static const String _metaFileName = 'modules_runtime_meta.json';

  static Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_localFileName');
  }

  static Future<File> _metaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_metaFileName');
  }

  static int _extractAssetVersion(Map<String, dynamic> data) {
    final value = data['asset_version'];
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 1;
  }

  static Future<Map<String, dynamic>> _readAssetJson() async {
    final raw = await rootBundle.loadString(_assetPath);
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>?> _readLocalJsonIfExists() async {
    final file = await _localFile();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>> _readMeta() async {
    final file = await _metaFile();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final raw = await file.readAsString();
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeMeta({
    required String bundledHash,
    required bool dirty,
  }) async {
    final file = await _metaFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'bundled_hash': bundledHash,
        'dirty': dirty,
      }),
      flush: true,
    );
  }

  static String _jsonFingerprint(Map<String, dynamic> data) {
    final raw = jsonEncode(data);
    var hash = 0x811C9DC5;
    for (final codeUnit in raw.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> _writeLocalJson(
    Map<String, dynamic> data, {
    required bool dirty,
    required String bundledHash,
  }) async {
    final file = await _localFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data), flush: true);
    await _writeMeta(bundledHash: bundledHash, dirty: dirty);
  }

  static Future<File> ensureLocalFile() async {
    final file = await _localFile();
    final assetJson = await _readAssetJson();
    final assetVersion = _extractAssetVersion(assetJson);
    final assetHash = _jsonFingerprint(assetJson);
    final meta = await _readMeta();
    final lastBundledHash = (meta['bundled_hash'] ?? '').toString();
    final dirty = meta['dirty'] == true;

    if (!await file.exists()) {
      await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
      return file;
    }

    final localJson = await _readLocalJsonIfExists();
    if (localJson == null) {
      await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
      return file;
    }

    final localVersion = _extractAssetVersion(localJson);
    final localHash = _jsonFingerprint(localJson);
    final metaMissing = lastBundledHash.isEmpty;

    if (metaMissing) {
      if (localHash != assetHash || assetVersion >= localVersion) {
        await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
      } else {
        await _writeMeta(bundledHash: assetHash, dirty: true);
      }
      return file;
    }

    if (lastBundledHash != assetHash && !dirty) {
      await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
      return file;
    }

    if (assetVersion > localVersion && !dirty) {
      await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
      return file;
    }

    if (lastBundledHash != assetHash && dirty) {
      await _writeMeta(bundledHash: assetHash, dirty: true);
    }

    return file;
  }

  static Future<Map<String, dynamic>> loadJson() async {
    final file = await ensureLocalFile();
    final raw = await file.readAsString();
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  static Future<ModulesData> load() async {
    return ModulesData.fromJson(await loadJson());
  }

  static Future<void> saveJson(Map<String, dynamic> data, {bool markDirty = true}) async {
    final assetJson = await _readAssetJson();
    final assetHash = _jsonFingerprint(assetJson);
    await _writeLocalJson(data, dirty: markDirty, bundledHash: assetHash);
  }

  static Future<void> resetFromAsset() async {
    final assetJson = await _readAssetJson();
    final assetHash = _jsonFingerprint(assetJson);
    await _writeLocalJson(assetJson, dirty: false, bundledHash: assetHash);
  }

}

class VirtusPrivacyApp extends StatelessWidget {
  const VirtusPrivacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtus Privacy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<ModulesData> _loadModules() async {
    return ModulesRepository.load();
  }

  IconData _iconForArea(String name) {
    final n = name.toLowerCase();
    if (n.contains('nutriz')) return Icons.restaurant_menu;
    if (n.contains('fisio')) return Icons.healing;
    if (n.contains('osteopatia pedi')) return Icons.child_care;
    if (n.contains('osteop')) return Icons.self_improvement;
    if (n.contains('masso')) return Icons.spa;
    if (n.contains('logop')) return Icons.record_voice_over;
    if (n.contains('ortott')) return Icons.visibility;
    if (n.contains('ostetr')) return Icons.family_restroom;
    if (n.contains('chinesi')) return Icons.fitness_center;
    if (n.contains('corsi')) return Icons.menu_book;
    if (n.contains('virtus')) return Icons.business;
    return Icons.folder_open;
  }

  Future<void> _openAdmin() async {
    if (AppAdminConfig.adminPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password admin non configurata.')),
      );
      return;
    }

    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accesso Admin'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            Navigator.of(dialogContext).pop(controller.text == AppAdminConfig.adminPassword);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text == AppAdminConfig.adminPassword),
            child: const Text('Entra'),
          ),
        ],
      ),
    );

    if (ok != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password admin non corretta')),
        );
      }
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ModulesData>(
      future: _loadModules(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Virtus Privacy')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: Text('Errore caricamento modules.json\n${snap.error}')),
            ),
          );
        }

        final data = snap.data!;
        final areas = data.areas.where((a) => a.active).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF2F2F2F),
            foregroundColor: Colors.white,
            title: const Text('Virtus Privacy'),
            actions: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    'Home',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openAdmin,
                icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
                label: const Text(
                  'Admin',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 110,
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.image_not_supported, size: 72),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Virtus Group s.r.l.',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Nutrizione e terapia dello sport\nVia Corfù 71 e via Montello 79 – Brescia\nTel. 0304096895 e 3518899843\nEmail: virtusgroup2023@gmail.com',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black87, height: 1.35),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Seleziona un\'area',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final cols = w >= 980 ? 3 : (w >= 640 ? 2 : 1);

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: areas.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            childAspectRatio: 3.2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemBuilder: (context, i) {
                            final area = areas[i];
                            return FilledButton.tonalIcon(
                              onPressed: () {
                                final pros = data.professionals
                                    .where((p) => p.active && p.areaId == area.id)
                                    .toList()
                                  ..sort((a, b) => a.name.compareTo(b.name));

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProfessionalsPage(area: area, professionals: pros),
                                  ),
                                );
                              },
                              icon: Icon(_iconForArea(area.name)),
                              label: Text(area.name),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfessionalsPage extends StatelessWidget {
  final AreaModel area;
  final List<ProfessionalModel> professionals;

  const ProfessionalsPage({
    super.key,
    required this.area,
    required this.professionals,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...professionals]..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: Text(area.name)),
      body: sorted.isEmpty
          ? const Center(child: Text('Nessun professionista attivo'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final cols = w >= 760 ? 3 : (w >= 520 ? 2 : 1);

                        return GridView.builder(
                          itemCount: sorted.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            childAspectRatio: 3.2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemBuilder: (context, index) {
                            final pro = sorted[index];
                            final hasPrivacy = pro.hasPrivacy;

                            return FilledButton.tonal(
                              onPressed: hasPrivacy
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ModulePage(
                                            professional: pro,
                                            areaName: area.name,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    pro.buttonTitle,
                                    textAlign: TextAlign.center,
                                  ),
                                  if (!hasPrivacy) ...[
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Privacy non presente',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Torna alla home'),
                  ),
                ],
              ),
            ),
    );
  }
}

class ModulePage extends StatefulWidget {
  final ProfessionalModel professional;
  final String areaName;

  const ModulePage({super.key, required this.professional, required this.areaName});

  @override
  State<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<ModulePage> {
  final Map<String, dynamic> _formData = {};
  final Map<String, SignatureController> _sigControllers = {};
  bool _saving = false;

  // Lingua dell'interfaccia del modulo: config.ui.lang ("it" di default, "en" per i moduli in inglese).
  bool get _en {
    final ui = widget.professional.config['ui'];
    return ui is Map && (ui['lang'] ?? '').toString().toLowerCase() == 'en';
  }

  String _t(String it, String en) => _en ? en : it;

  // ---------------------------
  // HTML / testo -> plain text (PDF)
  // - pulisce NBSP e caratteri “invisibili” che spesso diventano quadratini
  // - gestisce <br> / <p> / </li>
  // ---------------------------
  String _htmlToText(String html) {
    var t = html;

    // normalizza HTML entities frequenti
    t = t.replaceAll('&nbsp;', ' ');
    t = t.replaceAll('&amp;', '&');
    t = t.replaceAll('&quot;', '"');
    t = t.replaceAll('&#39;', "'");

    // normalizza spazi speciali unicode
    t = t.replaceAll('\u00A0', ' '); // NBSP
    t = t.replaceAll('\u202F', ' '); // narrow NBSP
    t = t.replaceAll('\u2007', ' '); // figure space
    t = t.replaceAll('\u2060', '');  // word joiner
    t = t.replaceAll('\u200B', '');  // zero width space
    t = t.replaceAll('\uFEFF', '');  // BOM
    t = t.replaceAll('\uFFFD', ' '); // replacement

    // break lines “sensati” prima di togliere tag
    t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
    t = t.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');

    // rimuovi tag
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');

    // pulizia finale
    t = t.replaceAll(RegExp(r'[\r\t]+'), ' ');
    t = t.replaceAll(RegExp(r'[ ]+\n'), '\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    t = t.replaceAll(RegExp(r' {2,}'), ' ').trim();

    // rimuovi control chars non stampabili
    final sb = StringBuffer();
    for (final r in t.runes) {
      if (r == 0x0A || r == 0x0D) {
        sb.writeCharCode(0x0A);
        continue;
      }
      if (r < 0x20) continue;
      // strip bidi/zero-width/invisible controls (they show up as □ in PDFs)
      if (r == 0x200B || r == 0x200C || r == 0x200D || r == 0x200E || r == 0x200F) continue;
      if (r >= 0x202A && r <= 0x202E) continue;
      if (r >= 0x2066 && r <= 0x2069) continue;
      if (r == 0xFEFF) continue;
      sb.writeCharCode(r);
    }
    return sb.toString().trim();
  }

  // ---------------------------
  // DEDUP INFORMATIVA (Messineo/Buizza)
  // ---------------------------
  String _normHtml(String s) {
    var t = s;
    t = t.replaceAll('&nbsp;', ' ');
    t = t.replaceAll('\u00A0', ' ');
    t = t.replaceAll('\u202F', ' ');
    t = t.replaceAll(RegExp(r'<[^>]*>'), ' ');
    t = t.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  List<String> _makeNeedles(String info, {int span = 140}) {
    if (info.length <= span) return [info];
    final out = <String>[];
    final len = info.length;
    final positions = <int>{0, (len * 0.33).floor(), (len * 0.66).floor(), len - span};
    for (final p in positions) {
      final start = p.clamp(0, len - 1);
      final end = (start + span).clamp(0, len);
      if (end > start) out.add(info.substring(start, end));
    }
    out.add(info.substring(0, 80.clamp(0, info.length)));
    out.add(info.substring((info.length - 80).clamp(0, info.length), info.length));
    return out.map((e) => e.trim()).where((e) => e.length >= 40).toList();
  }

  bool _blockLooksLikeInformativa(String informativaHtml, Map<String, dynamic> block) {
    final type = (block['type'] ?? '').toString();
    if (type != 'text_block' && type != 'html') return false;

    final info = _normHtml(informativaHtml);
    if (info.length < 120) return false;

    final blockText = _normHtml(
      type == 'text_block'
          ? (block['content'] ?? '').toString()
          : (block['html'] ?? '').toString(),
    );
    if (blockText.length < 120) return false;

    final needles = _makeNeedles(info);
    for (final nd in needles) {
      if (blockText.contains(nd)) return true;
    }
    return false;
  }

  bool _blocksContainInformativa(String informativaHtml, List<Map<String, dynamic>> blocks) {
    for (final b in blocks) {
      if (_blockLooksLikeInformativa(informativaHtml, b)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _dedupBlocks({
    required List<Map<String, dynamic>> blocks,
    required String informativaHtml,
    required bool showInformativaCard,
  }) {
    final out = <Map<String, dynamic>>[];
    String prevKey = '';

    for (final b in blocks) {
      final type = (b['type'] ?? '').toString();

      if (showInformativaCard && informativaHtml.isNotEmpty && _blockLooksLikeInformativa(informativaHtml, b)) {
        continue;
      }

      String content = '';
      if (type == 'text_block') content = _normHtml((b['content'] ?? '').toString());
      if (type == 'html') content = _normHtml((b['html'] ?? '').toString());

      final key = (content.isNotEmpty && content.length > 60) ? '$type:$content' : '';
      if (key.isNotEmpty && key == prevKey) continue;

      if (key.isNotEmpty) prevKey = key;
      out.add(b);
    }

    return out;
  }

  // ---------------------------
  // FIRME
  // ---------------------------
  SignatureController _sigForKey(String key) {
    return _sigControllers.putIfAbsent(
      key,
      () => SignatureController(
        penStrokeWidth: 3,
        penColor: Colors.black,
        exportBackgroundColor: Colors.white,
      ),
    );
  }

  bool _isSigRequired(Map<String, dynamic> block) {
    final v = (block['validation'] as Map?)?['required'];
    if (v is bool) return v;
    final direct = block['required'];
    if (direct is bool) return direct;
    return true; // default: firme richieste
  }

  bool _isFieldRequired(Map<String, dynamic> block) {
    return ((block['validation'] as Map?)?['required'] == true) || (block['required'] == true);
  }

  // ---------------------------
  // VALIDAZIONE: blocchi required + firme required + nome/cognome (se presente)
  // ---------------------------
  Map<String, String> _buildLabelsMap(List<Map<String, dynamic>> blocks) {
    final out = <String, String>{};

    void walk(Map<String, dynamic> b) {
      final type = (b['type'] ?? '').toString();
      if (type == 'text_input' || type == 'choice' || type == 'date' || type == 'signature') {
        final k = _dataKey(b);
        final lab = (b['label'] ?? '').toString().trim();
        if (k.isNotEmpty && lab.isNotEmpty) out[k] = lab;
      }
      if (type == 'inline_sentence') {
        final parts = (b['parts'] as List?) ?? [];
        for (final p in parts) {
          if (p is Map && p['field'] is Map) {
            final f = (p['field'] as Map).cast<String, dynamic>();
            final k = _dataKey(f);
            final lab = (f['label'] ?? f['placeholder'] ?? '').toString().trim();
            if (k.isNotEmpty && lab.isNotEmpty) out[k] = lab;
          }
        }
      }
      for (final c in _extractChildren(b)) {
        walk(c);
      }
    }

    for (final b in blocks) {
      walk(b);
    }
    return out;
  }

  List<Map<String, dynamic>> _collectRequiredBlocks(List<Map<String, dynamic>> blocks) {
    final out = <Map<String, dynamic>>[];

    void walk(Map<String, dynamic> b) {
      final type = (b['type'] ?? '').toString();
      if ((type == 'text_input' || type == 'choice' || type == 'date') && _isFieldRequired(b)) {
        out.add(b);
      }
      if (type == 'signature' && _isSigRequired(b)) {
        out.add(b);
      }
      if (type == 'inline_sentence') {
        final parts = (b['parts'] as List?) ?? [];
        for (final p in parts) {
          if (p is Map && p['field'] is Map) {
            final f = (p['field'] as Map).cast<String, dynamic>();
            final fType = (f['type'] ?? '').toString();
            if ((fType == 'text_input' || fType == 'choice' || fType == 'date') && _isFieldRequired(f)) {
              out.add(f);
            }
          }
        }
      }
      for (final c in _extractChildren(b)) {
        walk(c);
      }
    }

    for (final b in blocks) {
      walk(b);
    }
    return out;
  }

  String _guessPatientName(List<Map<String, dynamic>> blocks) {
    // Prova per chiavi comuni + fallback (prima field che contiene "nome" e "cognome")
    final candidates = [
      'patient.full_name',
      'patient_full_name',
      'paziente_nome_cognome',
      'nome_cognome',
      'full_name',
      'patient_name',
      // Moduli specifici che usano data_key non standard.
      // Serioli ha due campi inline dedicati e non usa patient.full_name.
      'serioli_paziente_full_name',
      'serioli_tutore_full_name',
    ];

    for (final k in candidates) {
      final v = (_formData[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    String? name;
    String? surname;

    for (final entry in _formData.entries) {
      final k = entry.key.toLowerCase();
      final v = entry.value.toString().trim();
      if (v.isEmpty) continue;

      if (k.contains('nome') && !k.contains('cognome') && name == null) name = v;
      if (k.contains('cognome') && surname == null) surname = v;

      if (k.contains('nome') && k.contains('cognome')) return v;
    }

    if ((name ?? '').isNotEmpty && (surname ?? '').isNotEmpty) return '$name $surname';
    if ((name ?? '').isNotEmpty) return name!;
    if ((surname ?? '').isNotEmpty) return surname!;
    return '';
  }

  bool _validateBeforeSave(List<Map<String, dynamic>> blocks) {
    final requiredBlocks = _collectRequiredBlocks(blocks);
    final labels = _buildLabelsMap(blocks);

    final missing = <String>[];

    // regola extra: Nome e Cognome (sempre)
    final patientName = _guessPatientName(blocks);
    if (patientName.trim().isEmpty) {
      missing.add(_t('Nome e Cognome', 'First and last name'));
    }

    for (final b in requiredBlocks) {
      final type = (b['type'] ?? '').toString();
      final k = _dataKey(b);
      final label = labels[k] ?? (b['label'] ?? b['placeholder'] ?? '').toString();
      final show = label.isNotEmpty ? label : k;

      if (type == 'signature') {
        final c = _sigControllers[k];
        if (c == null || c.isEmpty) missing.add(show);
        continue;
      }

      final v = (_formData[k] ?? '').toString().trim();
      if (v.isEmpty) missing.add(show);
    }

    if (missing.isNotEmpty) {
      final unique = <String>{};
      final compact = <String>[];
      for (final m in missing) {
        final t = m.trim();
        if (t.isEmpty) continue;
        if (unique.add(t)) compact.add(t);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('Compila i campi obbligatori', 'Please fill in the required fields')}:\n- ${compact.join('\n- ')}'),
          duration: const Duration(seconds: 5),
        ),
      );
      return false;
    }

    return true;
  }

  // ---------------------------
  // UI BUILD
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final pro = widget.professional;
    final config = pro.config;
    final ui = (config['ui'] is Map<String, dynamic>) ? config['ui'] as Map<String, dynamic> : <String, dynamic>{};

    final title = (ui['title'] ?? pro.displayTitle).toString();
    final subtitle = (ui['subtitle'] ?? '').toString();
    final informativa = (config['testo_informativa'] ?? '').toString();
    final informativaPosition = (ui['informativa_position'] ?? 'top').toString();

    final originalBlocks = pro.blocks;
    final infoAlreadyInBlocks = informativa.isNotEmpty && _blocksContainInformativa(informativa, originalBlocks);
    final showInformativaCard = informativa.isNotEmpty && !infoAlreadyInBlocks;

    final blocks = _dedupBlocks(
      blocks: originalBlocks,
      informativaHtml: informativa,
      showInformativaCard: showInformativaCard,
    );

    final List<Widget> children = [];

    if (showInformativaCard && informativaPosition == 'top') {
      children.add(_buildInformativaCard(informativa));
      children.add(const SizedBox(height: 16));
    }

    for (int i = 0; i < blocks.length; i++) {
      if (showInformativaCard && informativaPosition == 'after_first' && i == 1) {
        children.add(_buildInformativaCard(informativa));
        children.add(const SizedBox(height: 16));
      }
      children.add(_buildBlock(blocks[i]));
      children.add(const SizedBox(height: 16));
    }

    if (showInformativaCard && informativaPosition != 'top' && informativaPosition != 'after_first') {
      children.add(_buildInformativaCard(informativa));
      children.add(const SizedBox(height: 16));
    }

    return Scaffold(
      appBar: AppBar(title: Text(pro.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 18),
            ...children,
            const SizedBox(height: 90), // spazio per non finire sotto il bottom button
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!_validateBeforeSave(blocks)) return;

                    final outFile = await _savePdfLocal(blocks, informativa: informativa);
                    if (!mounted || outFile == null) return;

                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => SaveCompletedPage(pdfFile: outFile, english: _en),
                      ),
                    );
                  },
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? _t('Salvataggio...', 'Saving...') : _t('Salva modulo', 'Save form')),
          ),
        ),
      ),
    );
  }

  Widget _buildInformativaCard(String html) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Html(data: html),
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final type = (block['type'] ?? '').toString();
    final subtype = (block['subtype'] ?? '').toString();

    if (type == 'date' || subtype == 'date') {
      return _buildDateField(block);
    }

    switch (type) {
      case 'text_block':
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Html(data: (block['content'] ?? '').toString()),
          ),
        );

      case 'html':
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Html(data: (block['html'] ?? '').toString()),
          ),
        );

      case 'text_input':
        return _buildTextField(block);

      case 'choice':
        return _buildChoiceField(block);

      case 'section':
        final title = (block['title'] ?? '').toString();
        final children = _extractChildren(block);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.trim().isNotEmpty) ...[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                ],
                ...children.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildBlock(c),
                    )),
              ],
            ),
          ),
        );

      case 'row':
        final rowChildren = _extractChildren(block);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rowChildren
              .map((c) => SizedBox(width: 320, child: _buildBlock(c)))
              .toList(),
        );

      case 'inline_sentence':
        return _buildInlineSentence(block);

      case 'signature':
        final key = _dataKey(block);
        final label = _label(block);
        final required = _isSigRequired(block);
        final controller = _sigForKey(key);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(required ? '$label *' : label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Signature(
                      controller: controller,
                      height: 155,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      controller.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                    label: Text(_t('Cancella firma', 'Clear signature')),
                  ),
                ),
              ],
            ),
          ),
        );

      default:
        return Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Blocco non gestito: $type'),
          ),
        );
    }
  }

  // ---------------------------
  // INLINE SENTENCE
  // - Lorenzini: forza "residente a ..." ad andare a capo
  // - toglie virgola dopo "nato/a il,"
  // ---------------------------
  Widget _buildInlineSentence(Map<String, dynamic> block) {
    final parts = (block['parts'] as List<dynamic>? ?? []);
    final bool noWrapRequested = block['no_wrap'] == true;

    bool forceWrap = false;
    for (final p in parts) {
      if (p is Map && p.containsKey('text')) {
        final t = (p['text'] ?? '').toString().toLowerCase();
        if (t.contains('residente a')) {
          forceWrap = true;
          break;
        }
      }
      if (p is Map && p.containsKey('field')) {
        final f = (p['field'] as Map).cast<String, dynamic>();
        final ph = (f['placeholder'] ?? '').toString().toLowerCase();
        final dk = (f['data_key'] ?? '').toString().toLowerCase();
        if (ph.contains('residenza') || dk.contains('residenza')) {
          forceWrap = true;
          break;
        }
      }
    }

    final children = <Widget>[];

    for (final part in parts) {
      final map = (part as Map).cast<String, dynamic>();

      if (map.containsKey('text')) {
        var txt = map['text'].toString();

        // fix virgola “fastidiosa”
        txt = txt.replaceAll('nato/a il,', 'nato/a il');
        txt = txt.replaceAll('nata/o il,', 'nata/o il');

        if (txt.toLowerCase().contains('residente a')) {
          children.add(const SizedBox(width: double.infinity));
        }
        children.add(Text(txt, style: const TextStyle(fontSize: 16)));
        continue;
      }

      if (map.containsKey('field')) {
        final field = (map['field'] as Map).cast<String, dynamic>();
        final w = _fieldWidth(field);

        children.add(SizedBox(
          width: w,
          child: _buildInlineField(field),
        ));
        continue;
      }

      children.add(const SizedBox.shrink());
    }

    final bool noWrap = noWrapRequested && !forceWrap;

    if (noWrap) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _withSmallSpacing(children)),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  double _fieldWidth(Map<String, dynamic> field) {
    final raw = field['width_px'] ?? field['width'];
    double w = 200;

    if (raw is num) w = raw.toDouble();
    if (raw is String) {
      final parsed = double.tryParse(raw);
      if (parsed != null) w = parsed;
    }

    final ph = (field['placeholder'] ?? '').toString().toLowerCase();
    final dk = (field['data_key'] ?? '').toString().toLowerCase();
    if (ph.contains('residenza') || dk.contains('residenza')) {
      return 220;
    }

    if (w < 140) w = 140;
    if (w > 320) w = 320;
    return w;
  }

  Widget _buildInlineField(Map<String, dynamic> field) {
    final type = (field['type'] ?? '').toString();
    final subtype = (field['subtype'] ?? '').toString();

    if (type == 'date' || subtype == 'date') {
      return _buildDateField(field, dense: true);
    }

    switch (type) {
      case 'text_input':
        return _buildTextField(field, dense: true);
      case 'choice':
        return _buildChoiceField(field, dense: true);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextField(Map<String, dynamic> block, {bool dense = false}) {
    final key = _dataKey(block);
    final label = _label(block);
    final placeholder = (block['placeholder'] ?? '').toString();
    final required = _isFieldRequired(block);

    return TextFormField(
      initialValue: _formData[key]?.toString(),
      onChanged: (value) => _formData[key] = value,
      decoration: InputDecoration(
        isDense: dense,
        border: const OutlineInputBorder(),
        labelText: label.isNotEmpty ? (required ? '$label *' : label) : null,
        hintText: placeholder.isNotEmpty ? placeholder : null,
      ),
    );
  }

  Widget _buildDateField(Map<String, dynamic> block, {bool dense = false}) {
    final key = _dataKey(block);
    final label = _label(block);
    final required = _isFieldRequired(block);
    final current = _formData[key]?.toString();

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          setState(() {
            _formData[key] = _fmtDate(picked);
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: dense,
          border: const OutlineInputBorder(),
          labelText: label.isNotEmpty ? (required ? '$label *' : label) : _t('Data', 'Date'),
        ),
        child: Text(current ?? _t('Seleziona data', 'Select date')),
      ),
    );
  }

  Widget _buildChoiceField(Map<String, dynamic> block, {bool dense = false}) {
    final key = _dataKey(block);
    final label = _label(block);
    final required = _isFieldRequired(block);
    final render = (block['render'] ?? 'radio').toString();
    final options = (block['options'] as List<dynamic>? ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    if (render == 'select') {
      return DropdownButtonFormField<String>(
        value: _formData[key]?.toString(),
        decoration: InputDecoration(
          isDense: dense,
          border: const OutlineInputBorder(),
          labelText: label.isNotEmpty ? (required ? '$label *' : label) : null,
        ),
        items: options
            .map(
              (o) => DropdownMenuItem<String>(
                value: o['value']?.toString(),
                child: Text(o['label']?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged: (value) {
          setState(() {
            _formData[key] = value;
          });
        },
      );
    }

    final inlineOptions = block['inline_options'] == true;
    final labelAfterOptions = block['label_after_options'] == true;
    final hideLabel = block['hide_label'] == true;
    final introLabel = (block['intro_label'] ?? '').toString().trim();

    final radioWidgets = options.map<Widget>((o) {
      final value = o['value']?.toString();
      final text = o['label']?.toString() ?? '';

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(
            value: value ?? '',
            groupValue: _formData[key]?.toString(),
            onChanged: (v) {
              setState(() {
                _formData[key] = v;
              });
            },
          ),
          Flexible(child: Text(text)),
        ],
      );
    }).toList();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: inlineOptions
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (introLabel.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: Text(introLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  if (!hideLabel && !labelAfterOptions && label.isNotEmpty)
                    SizedBox(width: double.infinity, child: Text(required ? '$label *' : label)),
                  ...radioWidgets,
                  if (!hideLabel && labelAfterOptions && label.isNotEmpty)
                    SizedBox(width: double.infinity, child: Text(required ? '$label *' : label)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (introLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(introLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  if (!hideLabel && !labelAfterOptions && label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(required ? '$label *' : label),
                    ),
                  ...radioWidgets,
                  if (!hideLabel && labelAfterOptions && label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(required ? '$label *' : label),
                    ),
                ],
              ),
      ),
    );
  }

  List<Map<String, dynamic>> _extractChildren(Map<String, dynamic> block) {
    final raw = block['children'] ?? block['cols'] ?? block['blocks'] ?? [];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  String _dataKey(Map<String, dynamic> block) {
    final dk = (block['data_key'] ?? block['field'] ?? '').toString().trim();
    if (dk.isNotEmpty) return dk;

    final label = (block['label'] ?? '').toString().trim();
    if (label.isNotEmpty) return 'field_${_slug(label)}';

    return 'field_${block.hashCode}';
  }

  String _label(Map<String, dynamic> block) {
    return (block['label'] ?? '').toString();
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  List<Widget> _withSmallSpacing(List<Widget> items) {
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) out.add(const SizedBox(width: 6));
    }
    return out;
  }


  List<pw.Widget> _pdfSpaced(List<pw.Widget> items, {double height = 10}) {
    final out = <pw.Widget>[];
    for (int i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) {
        out.add(pw.SizedBox(height: height));
      }
    }
    return out;
  }

  pw.Widget _pdfTextCard(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Paragraph(
        text: text,
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
      ),
    );
  }

  pw.Widget _pdfValueBox({
    required String label,
    required String value,
  }) {
    return pw.Container(
      width: 240,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (label.trim().isNotEmpty)
            pw.Text(
              label.trim(),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          if (label.trim().isNotEmpty) pw.SizedBox(height: 4),
          pw.Text(value.trim(), style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  String _pdfChoiceSelectedLabel(Map<String, dynamic> block) {
    final key = _dataKey(block);
    final selected = (_formData[key] ?? '').toString().trim();
    if (selected.isEmpty) return '';

    final options = (block['options'] as List<dynamic>? ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    for (final o in options) {
      if ((o['value'] ?? '').toString() == selected) {
        final label = (o['label'] ?? '').toString().trim();
        return label.isEmpty ? selected : label;
      }
    }
    return selected;
  }

  String _pdfFieldValue(Map<String, dynamic> block) {
    final type = (block['type'] ?? '').toString();
    final subtype = (block['subtype'] ?? '').toString();
    if (type == 'choice') return _pdfChoiceSelectedLabel(block);
    if (type == 'date' || subtype == 'date') {
      return (_formData[_dataKey(block)] ?? '').toString().trim();
    }
    return (_formData[_dataKey(block)] ?? '').toString().trim();
  }

  String _pdfInlineSentenceText(Map<String, dynamic> block) {
    final parts = (block['parts'] as List<dynamic>? ?? []);
    final buf = StringBuffer();

    for (final raw in parts) {
      final part = (raw as Map).cast<String, dynamic>();
      if (part.containsKey('text')) {
        var txt = (part['text'] ?? '').toString();
        txt = txt.replaceAll('nato/a il,', 'nato/a il');
        txt = txt.replaceAll('nata/o il,', 'nata/o il');
        buf.write(txt);
        continue;
      }
      if (part.containsKey('field')) {
        final field = (part['field'] as Map).cast<String, dynamic>();
        final value = _pdfFieldValue(field);
        if (value.isNotEmpty) {
          buf.write(value);
        } else {
          buf.write('_____');
        }
      }
    }

    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _lowercaseFirst(String value) {
    if (value.isEmpty) return value;
    final first = value[0].toLowerCase();
    if (value.length == 1) return first;
    return '$first${value.substring(1)}';
  }

  Future<List<pw.Widget>> _pdfWidgetsFromBlocksAsync(
    List<Map<String, dynamic>> blocks, {
    required String patientName,
  }) async {
    final out = <pw.Widget>[];
    for (final block in blocks) {
      final widgets = await _pdfBlockAsync(block, patientName: patientName);
      if (widgets.isEmpty) continue;
      out.addAll(widgets);
      out.add(pw.SizedBox(height: 10));
    }
    if (out.isNotEmpty) out.removeLast();
    return out;
  }

  Future<List<pw.Widget>> _pdfBlockAsync(
    Map<String, dynamic> block, {
    required String patientName,
  }) async {
    final type = (block['type'] ?? '').toString();
    final subtype = (block['subtype'] ?? '').toString();

    if (type == 'date' || subtype == 'date') {
      final value = _pdfFieldValue(block);
      if (value.isEmpty) return [];
      return [
        _pdfValueBox(label: _label(block), value: value),
      ];
    }

    switch (type) {
      case 'text_block':
        final text = _htmlToText((block['content'] ?? '').toString()).trim();
        if (text.isEmpty) return [];
        return [_pdfTextCard(text)];

      case 'html':
        final text = _htmlToText((block['html'] ?? '').toString()).trim();
        if (text.isEmpty) return [];
        return [_pdfTextCard(text)];

      case 'text_input':
        final value = _pdfFieldValue(block);
        if (value.isEmpty) return [];
        return [
          _pdfValueBox(label: _label(block), value: value),
        ];

      case 'choice':
        final value = _pdfFieldValue(block);
        if (value.isEmpty) return [];

        final label = _label(block).trim();
        final labelAfterOptions = block['label_after_options'] == true;
        final introLabel = (block['intro_label'] ?? '').toString().trim();

        if (labelAfterOptions && label.isNotEmpty) {
          final prefix = introLabel.isNotEmpty ? '$introLabel ' : '';
          final sentence = '$prefix${_lowercaseFirst(value)} $label';
          return [
            pw.Paragraph(
              text: sentence,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
            ),
          ];
        }

        return [
          _pdfValueBox(label: label, value: value),
        ];

      case 'inline_sentence':
        final sentence = _pdfInlineSentenceText(block);
        if (sentence.isEmpty) return [];
        return [
          pw.Paragraph(
            text: sentence,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
          ),
        ];

      case 'row':
        final children = _extractChildren(block);
        final childWidgets = <pw.Widget>[];
        for (final c in children) {
          final built = await _pdfBlockAsync(c, patientName: patientName);
          childWidgets.addAll(built);
        }
        if (childWidgets.isEmpty) return [];
        return [
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: childWidgets,
          ),
        ];

      case 'section':
        final title = (block['title'] ?? '').toString().trim();
        final children = _extractChildren(block);
        final childWidgets = await _pdfWidgetsFromBlocksAsync(children, patientName: patientName);
        if (title.isEmpty && childWidgets.isEmpty) return [];
        return [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                if (title.isNotEmpty && childWidgets.isNotEmpty) pw.SizedBox(height: 10),
                ...childWidgets,
              ],
            ),
          ),
        ];

      case 'signature':
        final key = _dataKey(block);
        final controller = _sigControllers[key];
        if (controller == null || controller.isEmpty) return [];
        final png = await controller.toPngBytes();
        if (png == null) return [];
        var label = _label(block).trim();
        if (patientName.isNotEmpty && label.toLowerCase().contains('paziente')) {
          label = '$label - $patientName';
        }
        return [
          pw.NewPage(freeSpace: 150),
          _pdfSignatureBlock(label.isEmpty ? 'Firma' : label, png),
        ];

      default:
        return [];
    }
  }

  // ---------------------------
  // SALVATAGGIO PDF LOCALE
  // - percorso: Android/data/<package>/files/VirtusPrivacy/YYYY-MM/<area>/<professionista>/
  // - nome file: timestamp + professionista + paziente
  // ---------------------------
  String _slug(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), '_');
    t = t.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
    t = t.replaceAll(RegExp(r'_+'), '_');
    return t.isEmpty ? 'x' : t;
  }

  Future<Directory> _baseDir() async {
    if (Platform.isAndroid) {
      final visibleDownload = Directory('/storage/emulated/0/Download/VirtusPrivacy');
      try {
        if (!await visibleDownload.exists()) {
          await visibleDownload.create(recursive: true);
        }
        return visibleDownload;
      } catch (_) {
        final d = await getDownloadsDirectory();
        if (d != null) {
          final dir = Directory('${d.path}/VirtusPrivacy');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/VirtusPrivacy');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File?> _savePdfLocal(List<Map<String, dynamic>> blocks, {required String informativa}) async {
    setState(() => _saving = true);

    try {
      final pro = widget.professional;
      final config = pro.config;
      final ui = (config['ui'] is Map<String, dynamic>) ? config['ui'] as Map<String, dynamic> : <String, dynamic>{};
      final informativaPosition = (ui['informativa_position'] ?? 'top').toString();
      final originalBlocks = pro.blocks;
      final infoAlreadyInBlocks = informativa.isNotEmpty && _blocksContainInformativa(informativa, originalBlocks);
      final showInformativaCard = informativa.isNotEmpty && !infoAlreadyInBlocks;

      final patientName = _guessPatientName(blocks);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

      final base = await _baseDir();
      final ym = '${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}';
      final areaSlug = _slug(widget.areaName);
      final proSlug = _slug(pro.name);
      final pSlug = _slug(patientName.isEmpty ? 'paziente' : patientName);

      final outDir = Directory('${base.path}/$ym/$areaSlug/$proSlug');
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final outFile = File('${outDir.path}/${ts}_${proSlug}_${pSlug}.pdf');

      final contentWidgets = <pw.Widget>[];

      void addSpacer() {
        if (contentWidgets.isNotEmpty) {
          contentWidgets.add(pw.SizedBox(height: 10));
        }
      }

      void addInfoCard() {
        final infoText = _htmlToText(informativa).trim();
        if (infoText.isEmpty) return;
        if (contentWidgets.isNotEmpty) {
          contentWidgets.add(pw.SizedBox(height: 10));
        }
        contentWidgets.add(_pdfTextCard(infoText));
      }

      if (showInformativaCard && informativaPosition == 'top') {
        addInfoCard();
      }

      for (int i = 0; i < blocks.length; i++) {
        if (showInformativaCard && informativaPosition == 'after_first' && i == 1) {
          addInfoCard();
        }

        final built = await _pdfBlockAsync(blocks[i], patientName: patientName);
        if (built.isEmpty) continue;
        addSpacer();
        contentWidgets.addAll(built);
      }

      if (showInformativaCard && informativaPosition != 'top' && informativaPosition != 'after_first') {
        addInfoCard();
      }

      final regularFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
        ),
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
          build: (context) {
            final w = <pw.Widget>[];

            w.add(pw.Text(
              '${_t('Modulo Privacy', 'Privacy Form')} - ${pro.name}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ));
            w.add(pw.SizedBox(height: 6));
            w.add(pw.Text('Area: ${widget.areaName}', style: const pw.TextStyle(fontSize: 11)));
            w.add(pw.Text('${_t('Data', 'Date')}: $ts', style: const pw.TextStyle(fontSize: 11)));
            if (patientName.trim().isNotEmpty) {
              w.add(pw.Text('${_t('Paziente', 'Patient')}: $patientName', style: const pw.TextStyle(fontSize: 11)));
            }
            w.add(pw.SizedBox(height: 14));
            w.addAll(contentWidgets);
            return w;
          },
        ),
      );

      await outFile.writeAsBytes(await doc.save(), flush: true);
      return outFile;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('Errore salvataggio PDF', 'Error saving PDF')}: $e'), duration: const Duration(seconds: 5)),
      );
      return null;
    } finally {
      setState(() => _saving = false);
    }
  }

  pw.Widget _pdfSignatureBlock(String label, Uint8List pngBytes) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Image(pw.MemoryImage(pngBytes), height: 105),
          ),
          pw.SizedBox(height: 4),
          pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}


class SaveCompletedPage extends StatefulWidget {
  final File pdfFile;
  final bool english;

  const SaveCompletedPage({
    super.key,
    required this.pdfFile,
    this.english = false,
  });

  @override
  State<SaveCompletedPage> createState() => _SaveCompletedPageState();
}

class _SaveCompletedPageState extends State<SaveCompletedPage> {
  bool _opening = false;

  String _t(String it, String en) => widget.english ? en : it;

  Future<void> _openPdf() async {
    setState(() => _opening = true);
    try {
      final result = await OpenFilex.open(widget.pdfFile.path);
      if (!mounted) return;
      final type = result.type.toString().toLowerCase();
      if (!type.contains('done')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('Impossibile aprire il PDF', 'Unable to open the PDF')}: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('Errore apertura PDF', 'Error opening PDF')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Virtus Privacy'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t('Modulo salvato con successo!', 'Form saved successfully!'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 260,
                      child: OutlinedButton.icon(
                        onPressed: _opening ? null : _openPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(_opening ? _t('Apertura...', 'Opening...') : _t('Apri PDF', 'Open PDF')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 260,
                      child: FilledButton.icon(
                        onPressed: _goHome,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(
                          _t('Torna alla home', 'Back to home'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> get _areas => ((_data?['areas'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  List<Map<String, dynamic>> get _professionals => ((_data?['professionals'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await ModulesRepository.loadJson();
      if (!mounted) return;
      setState(() => _data = json);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist() async {
    if (_data == null) return;
    setState(() => _saving = true);
    try {
      await ModulesRepository.saveJson(_data!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurazione salvata.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _areaName(String areaId) {
    for (final a in _areas) {
      if ((a['id'] ?? '').toString() == areaId) {
        return (a['name'] ?? '').toString();
      }
    }
    return areaId;
  }

  Future<void> _resetFromAsset() async {
    await ModulesRepository.resetFromAsset();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moduli reimportati dagli asset.')),
    );
  }

  /// Same visible-Downloads folder already used for signed PDFs (see
  /// `_baseDir()` above) — proven to work on this app without any extra
  /// storage permission, so the backup file is easy to find in Files
  /// and easy to move between devices/app versions when needed (e.g. an
  /// app update that changes the release signing key, which forces a
  /// clean reinstall instead of an in-place update).
  Future<Directory> _configBackupDir() async {
    final dir = Directory('/storage/emulated/0/Download/VirtusPrivacy');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _exportConfiguration() async {
    if (_data == null) return;
    setState(() => _saving = true);
    try {
      final dir = await _configBackupDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/virtus_privacy_config_backup_$stamp.json');
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_data), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configurazione esportata: ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore esportazione: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Uses the system document picker (Storage Access Framework) rather than
  /// listing the Download/VirtusPrivacy folder directly: on a fresh install
  /// (e.g. after a signing-key change forces uninstall + reinstall, see
  /// `_exportConfiguration`) the app gets a new UID, and plain directory
  /// listing on shared storage can silently come back empty for files that
  /// UID didn't create — even though the files are still there. The system
  /// picker sidesteps that entirely: the OS grants read access to whatever
  /// the person taps, regardless of which app or UID originally wrote it.
  Future<void> _importConfiguration() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore selezione file: $e')),
      );
      return;
    }
    final path = result?.files.single.path;
    if (path == null) return; // cancelled
    final picked = File(path);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confermi il ripristino?'),
        content: Text('La configurazione attuale (aree e professionisti) verrà sostituita con il contenuto di "${picked.path.split(Platform.pathSeparator).last}". Questa azione non è reversibile.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Ripristina')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final raw = await picked.readAsString();
      final parsed = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (parsed['areas'] is! List || parsed['professionals'] is! List) {
        throw const FormatException('Il file non contiene un formato di configurazione valido.');
      }
      await ModulesRepository.saveJson(parsed);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurazione ripristinata.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore importazione: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _slugifyAreaId(String input) {
    var value = input.toLowerCase().trim();
    const replacements = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    replacements.forEach((k, v) => value = value.replaceAll(k, v));
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    value = value.replaceAll(RegExp(r'_+'), '_');
    value = value.replaceAll(RegExp(r'^_|_$'), '');
    if (value.isEmpty) value = 'nuova_area';
    return value;
  }

  int _nextAreaSortOrder() {
    var maxValue = 0;
    for (final area in _areas) {
      final value = (area['sort_order'] as num?)?.toInt() ?? int.tryParse('${area['sort_order'] ?? ''}') ?? 0;
      if (value > maxValue) maxValue = value;
    }
    return maxValue + 10;
  }

  Future<void> _addAreaDialog() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final sortCtrl = TextEditingController(text: _nextAreaSortOrder().toString());
    bool active = true;
    String? validationError;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            void syncIdFromName(String value) {
              idCtrl.text = _slugifyAreaId(value);
            }

            return AlertDialog(
              title: const Text('Nuova area'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome area',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocalState(() {
                        syncIdFromName(v);
                        validationError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ID area',
                        hintText: 'es. dentista',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() => validationError = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ordine',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visibile / attiva'),
                      value: active,
                      onChanged: (v) => setLocalState(() => active = v),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () {
                    final id = _slugifyAreaId(idCtrl.text.trim());
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setLocalState(() => validationError = 'Inserisci il nome area.');
                      return;
                    }
                    if (_areas.any((a) => (a['id'] ?? '').toString() == id)) {
                      setLocalState(() => validationError = 'ID area già presente.');
                      return;
                    }
                    idCtrl.text = id;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Crea'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;

    final areas = (_data!['areas'] as List<dynamic>);
    areas.add({
      'id': _slugifyAreaId(idCtrl.text.trim()),
      'name': nameCtrl.text.trim(),
      'sort_order': int.tryParse(sortCtrl.text.trim()) ?? _nextAreaSortOrder(),
      'active': active ? 1 : 0,
    });

    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _editAreaDialog(Map<String, dynamic> area) async {
    final originalId = (area['id'] ?? '').toString();
    final nameCtrl = TextEditingController(text: (area['name'] ?? '').toString());
    final idCtrl = TextEditingController(text: originalId);
    final sortCtrl = TextEditingController(text: ((area['sort_order'] ?? 9999)).toString());
    bool active = (area['active'] ?? 0).toString() == '1';
    String? validationError;
    final linkedProfessionals = _professionals.where((p) => (p['area_id'] ?? '').toString() == originalId).length;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Modifica area'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome area',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() => validationError = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ID area',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() => validationError = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ordine',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visibile / attiva'),
                      value: active,
                      onChanged: (v) => setLocalState(() => active = v),
                    ),
                    if (linkedProfessionals > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Professionisti collegati: $linkedProfessionals. Se cambi l\'ID, verranno aggiornati automaticamente.',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () {
                    final newName = nameCtrl.text.trim();
                    final newId = _slugifyAreaId(idCtrl.text.trim());
                    if (newName.isEmpty) {
                      setLocalState(() => validationError = 'Inserisci il nome area.');
                      return;
                    }
                    if (newId.isEmpty) {
                      setLocalState(() => validationError = 'Inserisci un ID valido.');
                      return;
                    }
                    if (_areas.any((a) => (a['id'] ?? '').toString() == newId && !identical(a, area))) {
                      setLocalState(() => validationError = 'ID area già presente.');
                      return;
                    }
                    idCtrl.text = newId;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    final newId = _slugifyAreaId(idCtrl.text.trim());
    area['name'] = nameCtrl.text.trim();
    area['id'] = newId;
    area['sort_order'] = int.tryParse(sortCtrl.text.trim()) ?? ((area['sort_order'] as num?)?.toInt() ?? 9999);
    area['active'] = active ? 1 : 0;

    if (newId != originalId) {
      final professionals = (_data!['professionals'] as List<dynamic>);
      for (final item in professionals) {
        final pro = (item as Map).cast<String, dynamic>();
        if ((pro['area_id'] ?? '').toString() == originalId) {
          pro['area_id'] = newId;
        }
      }
    }

    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _deleteArea(Map<String, dynamic> area) async {
    final areaId = (area['id'] ?? '').toString();
    final linkedProfessionals = _professionals.where((p) => (p['area_id'] ?? '').toString() == areaId).toList();
    if (linkedProfessionals.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile eliminare l\'area: ci sono ${linkedProfessionals.length} professionisti collegati.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina area'),
        content: Text('Vuoi eliminare l\'area ${(area['name'] ?? '').toString()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sì')),
        ],
      ),
    );
    if (ok != true) return;

    final areas = (_data!['areas'] as List<dynamic>);
    areas.removeWhere((e) => (e as Map)['id'].toString() == areaId);
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _addProfessionalDialog() async {
    final nameCtrl = TextEditingController();
    String? selectedAreaId = _areas.isNotEmpty ? (_areas.first['id'] ?? '').toString() : null;
    bool active = true;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Nuovo professionista'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome e cognome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedAreaId,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        border: OutlineInputBorder(),
                      ),
                      items: _areas
                          .map(
                            (a) => DropdownMenuItem<String>(
                              value: (a['id'] ?? '').toString(),
                              child: Text((a['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocalState(() => selectedAreaId = v),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visibile / attivo'),
                      value: active,
                      onChanged: (v) => setLocalState(() => active = v),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Verrà creato senza privacy: apparirà grigio finché non aggiungi il contenuto del modulo nel JSON.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Crea'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty || selectedAreaId == null || selectedAreaId!.isEmpty) return;

    final professionals = (_data!['professionals'] as List<dynamic>);
    professionals.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'area_id': selectedAreaId,
      'active': active ? 1 : 0,
      'config': {
        'ui': {'title': name},
        'testo_informativa': '',
        'blocks': [],
      },
    });

    await _persist();
    if (mounted) setState(() {});
  }


  Future<void> _editProfessionalDialog(Map<String, dynamic> pro) async {
    final nameCtrl = TextEditingController(text: (pro['name'] ?? '').toString());
    final config = (pro['config'] is Map<String, dynamic>)
        ? (pro['config'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final ui = (config['ui'] is Map<String, dynamic>)
        ? (config['ui'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final buttonCtrl = TextEditingController(
      text: (ui['button_title'] ?? '').toString(),
    );

    String? selectedAreaId = (pro['area_id'] ?? '').toString();
    bool active = (pro['active'] ?? 0).toString() == '1';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Modifica professionista'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome e cognome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: buttonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Testo bottone (facoltativo)',
                        hintText: 'Lascia vuoto per usare il nome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedAreaId,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        border: OutlineInputBorder(),
                      ),
                      items: _areas
                          .map(
                            (a) => DropdownMenuItem<String>(
                              value: (a['id'] ?? '').toString(),
                              child: Text((a['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocalState(() => selectedAreaId = v),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visibile / attivo'),
                      value: active,
                      onChanged: (v) => setLocalState(() => active = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty || selectedAreaId == null || selectedAreaId!.isEmpty) return;

    pro['name'] = newName;
    pro['area_id'] = selectedAreaId;
    pro['active'] = active ? 1 : 0;

    final cfg = (pro['config'] is Map<String, dynamic>)
        ? (pro['config'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final uiMap = (cfg['ui'] is Map<String, dynamic>)
        ? (cfg['ui'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final buttonText = buttonCtrl.text.trim();
    if (buttonText.isEmpty) {
      uiMap.remove('button_title');
    } else {
      uiMap['button_title'] = buttonText;
    }

    cfg['ui'] = uiMap;
    pro['config'] = cfg;

    await _persist();
    if (mounted) setState(() {});
  }


  Future<void> _deleteProfessional(Map<String, dynamic> pro) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina professionista'),
        content: Text('Vuoi eliminare ${(pro['name'] ?? '').toString()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sì')),
        ],
      ),
    );
    if (ok != true) return;

    final professionals = (_data!['professionals'] as List<dynamic>);
    professionals.removeWhere((e) => (e as Map)['id'].toString() == (pro['id'] ?? '').toString());
    await _persist();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2F2F2F),
        foregroundColor: Colors.white,
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Esporta configurazione (aree e professionisti)',
            onPressed: _loading || _saving ? null : _exportConfiguration,
            icon: const Icon(Icons.save_alt),
          ),
          IconButton(
            tooltip: 'Importa configurazione da backup',
            onPressed: _loading || _saving ? null : _importConfiguration,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'Reimporta moduli dagli asset',
            onPressed: _loading || _saving ? null : _resetFromAsset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_loading || _saving) ? null : _addProfessionalDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuovo professionista'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Configurazione non disponibile'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Aree',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _addAreaDialog,
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: const Text('Nuova area'),
                                ),
                                const SizedBox(width: 12),
                                if (_saving) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._areas.map((area) {
                              final active = (area['active'] ?? 0).toString() == '1';
                              final linkedProfessionals = _professionals.where((p) => (p['area_id'] ?? '').toString() == (area['id'] ?? '').toString()).length;
                              return Card(
                                elevation: 0,
                                color: Colors.grey.shade50,
                                child: ListTile(
                                  title: Text((area['name'] ?? '').toString()),
                                  subtitle: Text('ID: ${(area['id'] ?? '').toString()} • Ordine: ${area['sort_order'] ?? 9999} • Professionisti: $linkedProfessionals'),
                                  onTap: () => _editAreaDialog(area),
                                  leading: IconButton(
                                    tooltip: active ? 'Disattiva area' : 'Attiva area',
                                    onPressed: () async {
                                      area['active'] = active ? 0 : 1;
                                      setState(() {});
                                      await _persist();
                                    },
                                    icon: Icon(active ? Icons.toggle_on : Icons.toggle_off, color: active ? Colors.green : Colors.grey),
                                  ),
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifica area',
                                        onPressed: () => _editAreaDialog(area),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Elimina area',
                                        onPressed: () => _deleteArea(area),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Professionisti',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ..._professionals.map((pro) {
                              final active = (pro['active'] ?? 0).toString() == '1';
                              final hasPrivacy = ProfessionalModel.fromJson(pro).hasPrivacy;
                              return Card(
                                elevation: 0,
                                color: Colors.grey.shade50,
                                child: ListTile(
                                  title: Text((pro['name'] ?? '').toString()),
                                  subtitle: Text('${_areaName((pro['area_id'] ?? '').toString())} • ${hasPrivacy ? 'privacy presente' : 'privacy assente'}'),
                                  onTap: () => _editProfessionalDialog(pro),
                                  trailing: Wrap(
                                    spacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifica',
                                        onPressed: () => _editProfessionalDialog(pro),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      Switch(
                                        value: active,
                                        onChanged: (v) async {
                                          pro['active'] = v ? 1 : 0;
                                          setState(() {});
                                          await _persist();
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Elimina',
                                        onPressed: () => _deleteProfessional(pro),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
    );
  }
}

// ------------------------
// MODELS
// ------------------------
// MODELS
// ------------------------
class ModulesData {
  final List<AreaModel> areas;
  final List<ProfessionalModel> professionals;

  ModulesData({required this.areas, required this.professionals});

  factory ModulesData.fromJson(Map<String, dynamic> json) {
    final areas = (json['areas'] as List<dynamic>? ?? [])
        .map((e) => AreaModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final professionals = (json['professionals'] as List<dynamic>? ?? [])
        .map((e) => ProfessionalModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    return ModulesData(areas: areas, professionals: professionals);
  }
}

class AreaModel {
  final String id;
  final String name;
  final int sortOrder;
  final bool active;

  AreaModel({required this.id, required this.name, required this.sortOrder, required this.active});

  factory AreaModel.fromJson(Map<String, dynamic> json) {
    return AreaModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 9999,
      active: (json['active'] ?? 0).toString() == '1',
    );
  }
}

class ProfessionalModel {
  final String id;
  final String name;
  final String areaId;
  final bool active;
  final Map<String, dynamic> config;

  ProfessionalModel({
    required this.id,
    required this.name,
    required this.areaId,
    required this.active,
    required this.config,
  });

  factory ProfessionalModel.fromJson(Map<String, dynamic> json) {
    return ProfessionalModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      areaId: (json['area_id'] ?? '').toString(),
      active: (json['active'] ?? 0).toString() == '1',
      config: (json['config'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    );
  }

  String get displayTitle {
    final ui = (config['ui'] is Map<String, dynamic>) ? config['ui'] as Map<String, dynamic> : <String, dynamic>{};
    return (ui['title'] ?? name).toString();
  }

  String get buttonTitle {
    final ui = (config['ui'] is Map<String, dynamic>) ? config['ui'] as Map<String, dynamic> : <String, dynamic>{};
    return (ui['button_title'] ?? name).toString();
  }

  List<Map<String, dynamic>> get blocks {
    final raw = (config['blocks'] ?? []) as List<dynamic>;
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  bool get hasPrivacy {
    // Heuristica: privacy "vera" se c'è un testo informativa, oppure un blocco testo/html sostanzioso.
    final info = (config['testo_informativa'] ?? '').toString().trim();
    if (info.isNotEmpty) return true;

    final bs = blocks;
    bool hasBigText = false;
    for (final b in bs) {
      final t = (b['type'] ?? '').toString();
      if (t == 'text_block') {
        final c = (b['content'] ?? '').toString().trim();
        if (c.length > 80) {
          hasBigText = true;
          break;
        }
      }
      if (t == 'html') {
        final c = (b['html'] ?? '').toString().trim();
        if (c.length > 80) {
          hasBigText = true;
          break;
        }
      }
    }
    return hasBigText;
  }
}
