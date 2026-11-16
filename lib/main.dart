import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import 'ad_page.dart';
import 'app_localizations.dart';
import 'enhancer.dart';
import 'filament_test_page.dart';
import 'language_page.dart';
import 'languages.dart';
import 'person_tracking_test_page.dart';
import 'projects_page.dart';
import 'settings.dart';
import 'silence_cutter.dart';
import 'three_d_crash_guard.dart';
import 'three_d_diagnostics_page.dart';
import 'three_d_progress.dart';
import 'three_d_render_surface.dart';
import 'three_d_scene_pipeline.dart';
import 'timeline_preview_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If the last run ended abruptly inside the 3D phase, find out where, block
  // the suspect model and remember it so the home page can say so.
  try {
    await ThreeDCrashGuard.recoverPreviousCrash();
  } catch (_) {}

  runApp(const AutoEditApp());
}

class AutoEditApp extends StatefulWidget {
  const AutoEditApp({super.key});

  @override
  State<AutoEditApp> createState() => _AutoEditAppState();
}

class _AutoEditAppState extends State<AutoEditApp> {
  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final settings = await AppSettings.load();
      AppLocalizations.setLanguage(
        Languages.byCode(settings.country).lang,
      );
    } catch (_) {
      AppLocalizations.setLanguage('en');
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C5CFC);

    return ValueListenableBuilder<String>(
      valueListenable: AppLocalizations.language,
      builder: (context, language, child) {
        return MaterialApp(
          title: 'Wad Alreda Studio',
          debugShowCheckedModeBanner: false,
          locale: Locale(language),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLanguages
              .map((code) => Locale(code))
              .toList(),
          theme: ThemeData(
            colorSchemeSeed: seed,
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF0D0D14),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF11111B),
            ),
          ),
          builder: (context, child) {
            return Directionality(
              textDirection: AppLocalizations.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const WelcomePage(),
        );
      },
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF211847),
              Color(0xFF10101A),
              Color(0xFF08080D),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B70FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFF9A85FF),
                      width: 1.3,
                    ),
                  ),
                  child: const Icon(
                    Icons.movie_creation_outlined,
                    size: 55,
                    color: Color(0xFFB7A8FF),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Wad Alreda Studio',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.t('prophetBlessings'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE6D9FF),
                  ),
                ),
                const SizedBox(height: 38),
                Text(
                  AppLocalizations.t('welcomeTagline'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) =>
                              const LanguageGate(next: HomePage()),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        AppLocalizations.t('startNow'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PipelineOut {
  final CutResult cut;
  final EnhanceResult enhanced;

  _PipelineOut(this.cut, this.enhanced);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? inputPath;
  String? inputName;
  EnhanceResult? result;
  String? coverPath;

  String status = '@chooseVideoFirst';

  double? progress;
  bool busy = false;
  bool saving = false;

  /// Native Filament PlatformView identifier. Null while the view is not
  /// mounted.
  int? _threeDViewId;

  /// The user turned the 3D test view on with the button on its card.
  bool _showThreeDPanel = false;

  /// The 3D view is mounted automatically for the 3D phase of an export.
  bool _threeDExportActive = false;

  final ScrollController _scrollController = ScrollController();

  /// Set when the previous run ended abruptly inside the 3D phase.
  ThreeDBreadcrumb? _crashNotice;

  DateTime _lastProgressPaint = DateTime.fromMillisecondsSinceEpoch(0);

  /// The native Filament view renders continuously, which heats the phone, so
  /// it is only mounted while the user asks for it or an export needs it.
  bool get _threeDSurfaceMounted =>
      _showThreeDPanel || _threeDExportActive;

  @override
  void initState() {
    super.initState();
    _crashNotice = ThreeDCrashGuard.recovered;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// FFmpeg reports its statistics many times per second. Repainting the
  /// whole page (which holds the native 3D view) that often is wasteful and
  /// can starve the UI, so the bar is repainted at most ~2.5 times a second.
  /// A new status message is always painted at once.
  void _updateProgress({double? value, String? message}) {
    if (!mounted) return;

    final messageChanged = message != null && message != status;

    final now = DateTime.now();
    final due = now.difference(_lastProgressPaint) >=
        const Duration(milliseconds: 400);

    final valueChanged = value != null &&
        (progress == null || (value - progress!).abs() >= 0.005);

    if (!messageChanged && !(valueChanged && due)) return;

    _lastProgressPaint = now;

    setState(() {
      if (value != null) progress = value;
      if (message != null) status = message;
    });
  }

  void _openDiagnostics() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ThreeDDiagnosticsPage(),
      ),
    );
  }

  void _onThreeDPlatformViewCreated(int id) {
    if (!mounted || !_threeDSurfaceMounted) return;

    setState(() {
      _threeDViewId = id;
    });
  }

  /// Button on the 3D card: shows or hides the native 3D test view.
  void _toggleThreeDPanel() {
    if (busy) return;

    setState(() {
      _showThreeDPanel = !_showThreeDPanel;

      if (!_threeDSurfaceMounted) {
        _threeDViewId = null;
      }
    });
  }

  /// Mounts the 3D view for the 3D phase of an export and waits until the
  /// native view reports its id. Returns null if it never connects.
  Future<int?> _mountThreeDSurfaceForExport() async {
    if (!mounted) return null;

    setState(() {
      _threeDExportActive = true;
    });

    // The view must be on screen to be captured.
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }

    for (var attempt = 0; attempt < 100; attempt++) {
      final id = _threeDViewId;
      if (id != null) return id;

      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (!mounted) return null;
    }

    return _threeDViewId;
  }

  /// Unmounts the 3D view (frees its GPU memory and stops the heating).
  /// Safe to call more than once.
  Future<void> _releaseThreeDSurface() async {
    if (!_threeDExportActive &&
        !_showThreeDPanel &&
        _threeDViewId == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _threeDExportActive = false;
      _showThreeDPanel = false;
      _threeDViewId = null;
    });

    // Give the platform view a moment to free its memory before FFmpeg
    // starts the heavy compositing.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  Future<void> _pick() async {
    try {
      final picked =
          await FilePicker.platform.pickFiles(type: FileType.video);

      if (picked == null ||
          picked.files.isEmpty ||
          picked.files.single.path == null) {
        return;
      }

      if (!mounted) return;

      setState(() {
        inputPath = picked.files.single.path;
        inputName = picked.files.single.name;
        result = null;
        coverPath = null;
        progress = null;
        status =
            '${AppLocalizations.t('selectedVideo')}: ${picked.files.single.name}\n'
            '${AppLocalizations.t('pressStartEditing')}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '${AppLocalizations.t('pickFailedPrefix')}$e';
        });
      }
    }
  }

  /// Runs the original editing engine first, then adds native 3D scenes.
  ///
  /// The 3D stage runs after the ad page is closed. The native Filament view
  /// is mounted only for that stage and released as soon as the last scene is
  /// captured.
  Future<_PipelineOut> _pipeline(
    String source,
    AppSettings settings,
  ) async {
    CutResult? cut;

    try {
      cut = await SilenceCutter.process(
        source,
        noiseDb: settings.noiseDb,
        minSilence: settings.minSilence,
        onStatus: (message) {
          if (mounted) {
            setState(() => status = message);
          }
        },
        onProgress: (value) {
          _updateProgress(value: value * 0.12);
        },
      );

      final enhanced = await Enhancer.run(
        cutPath: cut.path,
        cutSec: cut.newSec,
        s: settings,
        cutTimes: cut.segStarts,
        onStatus: (message) {
          if (mounted) {
            setState(() => status = message);
          }
        },
        onProgress: (value) {
          _updateProgress(value: 0.12 + value * 0.68);
        },
      );

      final threeDEnabled = settings.online3DAssetsEnabled;
      int? viewId;

      if (threeDEnabled) {
        if (mounted) {
          setState(() {
            progress = 0.80;
            status = 'جاري تشغيل محرك 3D...';
          });
        }

        viewId = await _mountThreeDSurfaceForExport();
      }

      if (!threeDEnabled) {
        enhanced.notes.add(
          'مصادر المجسمات ثلاثية الأبعاد معطلة من الإعدادات؛ تم تصدير الفيديو الأساسي.',
        );
      } else if (viewId == null) {
        await _releaseThreeDSurface();

        enhanced.notes.add(
          'تم تصدير الفيديو الأساسي، لكن محرك 3D لم يتصل في الوقت المناسب؛ لم تتم إضافة مشاهد 3D.',
        );
      } else {
        if (mounted) {
          setState(() {
            progress = 0.80;
            status = 'جاري تجهيز مشاهد 3D وربطها بالتوقيتات...';
          });
        }

        try {
          final threeDResult = await ThreeDScenePipeline.apply(
            viewId: viewId,
            videoPath: enhanced.videoPath,
            timeline: enhanced.timelineProject,
            settings: settings,
            onStatus: (message) {
              _updateProgress(message: message);
            },
            onProgress: (ThreeDProgress live) {
              _updateProgress(value: live.overall(), message: live.message);
            },
            onRenderingDone: _releaseThreeDSurface,
          );

          enhanced.notes.addAll(threeDResult.notes);

          if (threeDResult.applied) {
            enhanced.notes.add(
              'تم دمج ${threeDResult.scenesRendered} مشهد 3D متحرك في الفيديو النهائي.',
            );
          }
        } finally {
          await _releaseThreeDSurface();
        }
      }

      if (mounted) {
        setState(() {
          progress = 0.98;
        });
      }

      return _PipelineOut(cut, enhanced);
    } catch (_) {
      if (cut != null) {
        try {
          File(cut.path).deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _run() async {
    final source = inputPath;
    if (source == null || busy) return;

    setState(() {
      busy = true;
      progress = 0;
      result = null;
      coverPath = null;
      status = '${AppLocalizations.t('editingStarted')}\n'
          '${AppLocalizations.t('adNotice')}';
    });

    try {
      final settings = await AppSettings.load();
      JobControl.reset();

      final adCompleted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AdPage()),
      );

      if (!mounted) return;

      if (adCompleted != true) {
        setState(() {
          progress = null;
          status = AppLocalizations.t('adExportStopped');
        });
        return;
      }

      setState(() {
        status = AppLocalizations.t('adFinished');
      });

      final out = await _pipeline(source, settings);

      if (!mounted) return;

      final cut = out.cut;
      final enhanced = out.enhanced;

      setState(() {
        result = enhanced;
        coverPath = enhanced.coverPath;
        progress = 1;

        status = '${AppLocalizations.t('videoReady')}\n'
            '${AppLocalizations.t('duration')}: '
            '${cut.originalSec.toStringAsFixed(1)}s → '
            '${cut.newSec.toStringAsFixed(1)}s\n'
            '${AppLocalizations.t('resolution')}: '
            '${enhanced.outW}×${enhanced.outH}\n'
            '${AppLocalizations.t('size')}: '
            '${enhanced.sizeMb.toStringAsFixed(1)} MB'
            '${enhanced.notes.isEmpty ? '' : '\n\n${AppLocalizations.t('notes')}:\n- ${enhanced.notes.join('\n- ')}'}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '${AppLocalizations.t('editingError')}\n$e';
        });
      }
    } finally {
      // Whatever happened, the native 3D view must not stay mounted.
      await _releaseThreeDSurface();

      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  String _postText() {
    final current = result!;
    final tags = current.hashtags.map((tag) => '#$tag').join(' ');
    return '${current.title}\n\n${current.description}\n\n$tags'.trim();
  }

  Future<void> _saveToGallery() async {
    final current = result;
    if (current == null || saving) return;

    setState(() {
      saving = true;
      status = AppLocalizations.t('savingToGallery');
    });

    try {
      await Gal.requestAccess(toAlbum: true);

      final allowed = await Gal.hasAccess(toAlbum: true);
      if (!allowed) {
        throw Exception(AppLocalizations.t('galleryPermission'));
      }

      await Gal.putVideo(
        current.videoPath,
        album: 'Wad Alreda Studio',
      );

      var message = AppLocalizations.t('videoSaved');

      if (coverPath != null && await File(coverPath!).exists()) {
        try {
          await Gal.putImage(
            coverPath!,
            album: 'Wad Alreda Studio',
          );
          message += '\n${AppLocalizations.t('coverSaved')}';
        } catch (_) {
          message += '\n${AppLocalizations.t('coverFailed')}';
        }
      }

      if (mounted) {
        setState(() => status = message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '${AppLocalizations.t('saveFailedPrefix')}$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> _share() async {
    final current = result;
    if (current == null) return;

    try {
      await Share.shareXFiles([
        XFile(current.videoPath),
        if (coverPath != null && await File(coverPath!).exists())
          XFile(coverPath!),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '${AppLocalizations.t('shareFailedPrefix')}$e';
        });
      }
    }
  }

  Future<void> _copyPostText() async {
    if (result == null) return;

    await Clipboard.setData(
      ClipboardData(text: _postText()),
    );

    if (mounted) {
      setState(() => status = AppLocalizations.t('postCopied'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = result;
    final crashNotice = _crashNotice;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wad Alreda Studio',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.isRtl
                ? 'تقرير تشخيص 3D'
                : '3D diagnostics report',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: busy ? null : _openDiagnostics,
          ),
          IconButton(
            tooltip: AppLocalizations.isRtl
                ? 'اختبار محرك 3D'
                : 'Filament 3D test',
            icon: const Icon(Icons.view_in_ar_rounded),
            onPressed: busy
                ? null
                : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const FilamentTestPage(),
                      ),
                    ),
          ),
          IconButton(
            tooltip: AppLocalizations.isRtl
                ? 'مكتبة المشاريع'
                : 'Project library',
            icon: const Icon(Icons.folder_copy_outlined),
            onPressed: busy
                ? null
                : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProjectsPage(),
                      ),
                    ),
          ),
          IconButton(
            tooltip: AppLocalizations.t('settings'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsPage(),
                      ),
                    ),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          if (crashNotice != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2C1820),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8A3B4F)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'التطبيق أُغلق فجأة في التصدير السابق أثناء: '
                    '${crashNotice.describe()}\n'
                    '${ThreeDCrashGuard.adviceFor(crashNotice)}',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy ? null : _openDiagnostics,
                        child: const Text('فتح تقرير 3D'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _crashNotice = null),
                        child: const Text('إخفاء'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF2A2150),
                  Color(0xFF171727),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF55438C).withValues(alpha: 0.65),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.t('prophetBlessings'),
                  style: const TextStyle(
                    color: Color(0xFFE8DFFF),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.t('welcomeTagline'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Silence cutting • Audio • Captions • B-roll • 3D • Cover',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          // The native Filament view is only mounted while the user turns it
          // on here or while an export is rendering its 3D scenes. It renders
          // continuously, so leaving it mounted all the time heats the phone.
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF171721),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF55438C),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.view_in_ar_rounded,
                      color: Color(0xFFB7A8FF),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Filament 3D Render Engine',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _threeDSurfaceMounted
                          ? (AppLocalizations.isRtl
                              ? 'إيقاف محرك 3D'
                              : 'Turn 3D engine off')
                          : (AppLocalizations.isRtl
                              ? 'تشغيل محرك 3D'
                              : 'Turn 3D engine on'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _threeDSurfaceMounted
                            ? Icons.block_rounded
                            : Icons.play_circle_outline_rounded,
                        color: busy
                            ? Colors.white24
                            : const Color(0xFFB7A8FF),
                      ),
                      onPressed: busy ? null : _toggleThreeDPanel,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_threeDSurfaceMounted) ...[
                  Center(
                    child: SizedBox(
                      width: 240,
                      child: ThreeDRenderSurface(
                        onPlatformViewCreated:
                            _onThreeDPlatformViewCreated,
                        height: 240,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_threeDExportActive) ...[
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppLocalizations.runtime(status).split('\n').first,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ] else
                    Text(
                      _threeDViewId == null
                          ? 'جاري تهيئة محرك 3D...'
                          : 'محرك 3D متصل وجاهز لاستقبال المشاهد.',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                ] else
                  const Text(
                    'محرك 3D متوقف لتقليل حرارة الجوال، ويعمل تلقائياً أثناء '
                    'التصدير فقط. اضغط زر التشغيل لتجربته.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),

          // Phase 1 manual test screen: visual person tracking.
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const PersonTrackingTestPage(),
                      ),
                    ),
            icon: const Icon(Icons.accessibility_new_rounded),
            label: Text(
              AppLocalizations.isRtl
                  ? 'اختبار تتبع الأشخاص (المرحلة 1)'
                  : 'Person tracking test (Phase 1)',
            ),
          ),

          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                inputName == null
                    ? AppLocalizations.t('chooseVideo')
                    : '${AppLocalizations.t('changeVideo')}: $inputName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (busy || inputPath == null) ? null : _run,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                busy
                    ? AppLocalizations.t('preparingVideo')
                    : AppLocalizations.t('startExport'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.t('adNotice'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white60,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (busy) ...[
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 6),
            Text(
              '${((progress ?? 0) * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171721),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              AppLocalizations.runtime(status),
              style: const TextStyle(
                fontSize: 14,
                height: 1.65,
              ),
            ),
          ),
          if (current != null) ...[
            if (coverPath != null && File(coverPath!).existsSync()) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(coverPath!),
                  height: 230,
                  fit: BoxFit.contain,
                  // Decode a small copy: a full-size 2K cover wastes memory
                  // right when the export finishes.
                  cacheHeight: 700,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TimelinePreviewPage(
                    project: current.timelineProject,
                    videoPath: current.videoPath,
                  ),
                ),
              ),
              icon: const Icon(Icons.timeline_rounded),
              label: Text(
                AppLocalizations.isRtl
                    ? 'فتح التايم لاين'
                    : 'Open timeline',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: saving ? null : _saveToGallery,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                saving
                    ? AppLocalizations.t('saving')
                    : AppLocalizations.t('saveVideo'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: Text(AppLocalizations.t('shareVideoCover')),
            ),
            if (current.title.isNotEmpty ||
                current.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                AppLocalizations.t('postDescription'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _postText(),
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              TextButton.icon(
                onPressed: _copyPostText,
                icon: const Icon(Icons.copy_all),
                label: Text(AppLocalizations.t('copyPost')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
