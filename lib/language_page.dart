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