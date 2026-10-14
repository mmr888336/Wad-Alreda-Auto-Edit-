import 'package:flutter/material.dart';
import 'languages.dart';
import 'settings.dart';

/// بعد الضغط على "ابدأ الآن": أول مرة فقط تظهر شاشة اختيار اللغة (الافتراضي English)،
/// وبعدها نفتح الصفحة الرئيسية مباشرة.
class LanguageGate extends StatefulWidget {
  final Widget next;
  const LanguageGate({super.key, required this.next});

  @override
  State<LanguageGate> createState() => _LanguageGateState();
}

class _LanguageGateState extends State<LanguageGate> {
  AppSettings? settings;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((value) {
      if (mounted) setState(() => settings = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = settings;
    if (current == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (current.onboarded) return widget.next;
    return LanguagePage(settings: current, next: widget.next);
  }
}

class LanguagePage extends StatefulWidget {
  final AppSettings settings;
  final Widget next;
  const LanguagePage({super.key, required this.settings, required this.next});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String selected = Languages.defaultCode;
  String query = '';

  Future<void> _continue() async {
    final current = widget.settings;
    current.country = selected;
    current.onboarded = true;
    await current.save();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final items = Languages.countries.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) || c.langName.contains(q) || c.dialect.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose your language • اختر لغتك'), automaticallyImplyLeading: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search • بحث',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'This sets the language of captions and titles. You can change it later in Settings.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final c = items[index];
                final on = c.code == selected;
                return ListTile(
                  title: Text(c.name),
                  subtitle: c.dialect.isEmpty ? null : Text(c.dialect),
                  trailing: Icon(on ? Icons.radio_button_checked : Icons.radio_button_off),
                  selected: on,
                  onTap: () => setState(() => selected = c.code),
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
                child: FilledButton(onPressed: _continue, child: const Text('Continue • متابعة')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
