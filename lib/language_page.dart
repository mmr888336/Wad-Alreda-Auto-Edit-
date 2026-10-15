import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'languages.dart';
import 'settings.dart';

class LanguageGate extends StatefulWidget {
  final Widget next;

  const LanguageGate({
    super.key,
    required this.next,
  });

  @override
  State<LanguageGate> createState() => _LanguageGateState();
}

class _LanguageGateState extends State<LanguageGate> {
  AppSettings? settings;

  @override
  void initState() {
    super.initState();

    AppSettings.load().then((value) {
      if (!mounted) return;

      setState(() => settings = value);

      AppLocalizations.setLanguage(
        Languages.byCode(value.country).lang,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = settings;

    if (current == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (current.onboarded) {
      return widget.next;
    }

    return LanguagePage(
      settings: current,
      next: widget.next,
    );
  }
}

class LanguagePage extends StatefulWidget {
  final AppSettings settings;
  final Widget next;

  const LanguagePage({
    super.key,
    required this.settings,
    required this.next,
  });

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  late String selected;
  String query = '';

  @override
  void initState() {
    super.initState();

    selected = widget.settings.country;

    AppLocalizations.setLanguage(
      Languages.byCode(selected).lang,
    );
  }

  Future<void> _continue() async {
    final current = widget.settings;

    current.country = selected;
    current.onboarded = true;

    await current.save();

    if (!mounted) return;

    AppLocalizations.setLanguage(
      Languages.byCode(selected).lang,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();

    final items = Languages.countries.where((country) {
      if (q.isEmpty) return true;

      return country.name.toLowerCase().contains(q) ||
          country.langName.toLowerCase().contains(q) ||
          country.dialect.toLowerCase().contains(q) ||
          country.code.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('languageSelect')),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: AppLocalizations.t('search'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              AppLocalizations.t('languageSelectDesc'),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final country = items[index];
                final isSelected = country.code == selected;

                return ListTile(
                  title: Text(country.name),
                  subtitle: country.dialect.isEmpty
                      ? null
                      : Text(country.dialect),
                  trailing: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  selected: isSelected,
                  onTap: () {
                    setState(() => selected = country.code);

                    AppLocalizations.setLanguage(country.lang);
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _continue,
                  child: Text(AppLocalizations.t('continue')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// يرسم النص كصورة PNG شفافة حتى يركّبه FFmpeg فوق الفيديو.
class TextRender {
  /// يحدد الاتجاه من أحرف النص، وليس من لغة واجهة التطبيق.
  static TextDirection _directionOf(String text) {
    for (final rune in text.runes) {
      // الحروف العربية والعبرية والكتابات من اليمين إلى اليسار.
      final isRtlLetter =
          (rune >= 0x05D0 && rune <= 0x05EA) ||
          (rune >= 0x05EF && rune <= 0x05F2) ||
          (rune >= 0x0620 && rune <= 0x064A) ||
          (rune >= 0x066E && rune <= 0x066F) ||
          (rune >= 0x0671 && rune <= 0x06D3) ||
          rune == 0x06D5 ||
          (rune >= 0x06E5 && rune <= 0x06E6) ||
          (rune >= 0x06EE && rune <= 0x06EF) ||
          (rune >= 0x06FA && rune <= 0x06FC) ||
          rune == 0x06FF ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08C9) ||
          (rune >= 0xFB1D && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF);

      if (isRtlLetter) return TextDirection.rtl;

      // الحروف اللاتينية واليونانية والسيريلية تُقرأ من اليسار لليمين.
      final isLtrLetter =
          (rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A) ||
          (rune >= 0x00C0 && rune <= 0x02AF) ||
          (rune >= 0x0370 && rune <= 0x03FF) ||
          (rune >= 0x0400 && rune <= 0x052F);

      if (isLtrLetter) return TextDirection.ltr;
    }

    // نص لا يحتوي على حرف واضح: نستخدم LTR كاتجاه افتراضي.
    return TextDirection.ltr;
  }

  static Future<String> png({
    required String text,
    required String outPath,
    required int width,
    required double fontSize,
    Color fill = Colors.white,
    Color stroke = Colors.black,
    bool box = false,
  }) async {
    final direction = _directionOf(text);
    final maxW = width * 0.9;
    final pad = fontSize * 0.35;
    final strokeW = fontSize * 0.2;

    TextPainter build(TextStyle style) => TextPainter(
          text: TextSpan(
            text: text,
            style: style,
          ),
          textDirection: direction,
          textAlign: TextAlign.center,
          maxLines: 3,
        )..layout(
            minWidth: maxW,
            maxWidth: maxW,
          );

    final back = build(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.3,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      ),
    );

    final front = build(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.3,
        color: fill,
      ),
    );

    final h = (back.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final left = (width - maxW) / 2;

    if (box) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            0,
            maxW,
            h.toDouble(),
          ),
          Radius.circular(fontSize * 0.4),
        ),
        Paint()..color = const Color(0xB3000000),
      );
    }

    back.paint(canvas, Offset(left, pad));
    front.paint(canvas, Offset(left, pad));

    final image = await recorder.endRecording().toImage(width, h);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (data == null) {
      throw Exception('Could not render caption image.');
    }

    await File(outPath).writeAsBytes(
      data.buffer.asUint8List(),
    );

    return outPath;
  }
}