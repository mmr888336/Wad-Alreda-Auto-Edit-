import 'dart:io';

import 'package:flutter/material.dart';

import 'project_store.dart';
import 'timeline_page.dart';

/// Project library screen. It is intentionally independent from main.dart so
/// navigation can be connected once the Studio entry points are consolidated.
class ProjectsPage extends StatefulWidget {
  final ProjectStore store;
  final ValueChanged<SavedProject>? onProjectOpened;

  const ProjectsPage({
    super.key,
    this.store = const ProjectStore(),
    this.onProjectOpened,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool _loading = true;
  String? _error;
  String? _openingProjectId;
  List<SavedProject> _projects = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final projects = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(SavedProject project) async {
    if (_openingProjectId != null) return;
    setState(() => _openingProjectId = project.id);

    try {
      // Reload from disk and validate every media path before opening.
      final latest = await widget.store.load(project.id);
      if (!mounted) return;

      final callback = widget.onProjectOpened;
      if (callback != null) {
        callback(latest);
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelinePage(
            project: latest.timelineProject,
          ),
        ),
      );
    } catch (error) {
      _showMessage('تعذر فتح المشروع أو توجد ملفات مفقودة: $error');
      await _reload();
    } finally {
      if (mounted) setState(() => _openingProjectId = null);
    }
  }

  Future<void> _rename(SavedProject project) async {
    final controller = TextEditingController(text: project.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة تسمية المشروع'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'اسم المشروع'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.trim().isEmpty) return;
    try {
      await widget.store.rename(project.id, newName);
      await _reload();
    } catch (error) {
      _showMessage('تعذرت إعادة التسمية: $error');
    }
  }

  Future<void> _delete(SavedProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المشروع؟'),
        content: Text(
          'سيتم حذف المشروع وملفاته المحفوظة من مساحة التطبيق:\n${project.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await widget.store.delete(project.id);
      await _reload();
      _showMessage('تم حذف المشروع وملفاته.');
    } catch (error) {
      _showMessage('تعذر حذف المشروع: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _date(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المشاريع المحفوظة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _reload)
              : _projects.isEmpty
                  ? const _EmptyProjectsView()
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _projects.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final project = _projects[index];
                          final duration =
                              project.timelineProject.duration.toStringAsFixed(1);
                          final hasCover = project.coverPath != null &&
                              File(project.coverPath!).existsSync();

                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 66,
                                  height: 76,
                                  child: hasCover
                                      ? Image.file(
                                          File(project.coverPath!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const _ProjectIcon(),
                                        )
                                      : const _ProjectIcon(),
                                ),
                              ),
                              title: Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '$duration ثانية  •  '
                                  '${project.timelineProject.tracks.length} مسارات\n'
                                  '${_date(project.updatedAt)}',
                                  maxLines: 2,
                                ),
                              ),
                              isThreeLine: true,
                              onTap: _openingProjectId == null
                                  ? () => _open(project)
                                  : null,
                              trailing: _openingProjectId == project.id
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _rename(project);
                                  } else if (value == 'delete') {
                                    _delete(project);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('إعادة تسمية'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('حذف المشروع'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ProjectIcon extends StatelessWidget {
  const _ProjectIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF28223F),
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_creation_outlined,
        color: Color(0xFFB7A8FF),
        size: 30,
      ),
    );
  }
}

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.video_library_outlined, size: 54, color: Colors.white54),
            SizedBox(height: 14),
            Text(
              'لا توجد مشاريع محفوظة حتى الآن',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'بعد تفعيل الحفظ التلقائي ستظهر مشاريعك هنا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}