import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_state.dart';
import 'cache.dart';
import 'glyph.dart';
import 'sources.dart';
import 'theme.dart';

/// iOS-style grouped settings, shown as a sheet over the feed.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VoidCallback onClose;
  final void Function(double dy) onDragUpdate;
  final void Function(double velocityY) onDragEnd;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final AppState app = AppState.instance;
  late final TextEditingController _folder =
      TextEditingController(text: app.folderPath);
  final TextEditingController _url = TextEditingController();
  int? _cacheBytes;
  bool _access = true;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    app.addListener(_refresh);
    _loadCache();
    _loadAccess();
  }

  @override
  void dispose() {
    app.removeListener(_refresh);
    _folder.dispose();
    _url.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCache() async {
    final b = await CacheService.sizeBytes();
    if (mounted) setState(() => _cacheBytes = b);
  }

  Future<void> _loadAccess() async {
    final ok = await Sources.hasAccess();
    if (mounted) setState(() => _access = ok);
  }

  String _size(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _askAccess() async {
    final ok = await Sources.requestAccess();
    if (!ok) await openAppSettings();
    app.markDirty();
    await _loadAccess();
  }

  Future<void> _pickFolder() async {
    try {
      await Sources.requestAccess();
      final String? path =
          await FilePicker.getDirectoryPath(dialogTitle: 'Choose your video folder');
      if (path == null || path.isEmpty) return;
      _folder.text = path;
      app.setFolderPath(path);
      if (!app.folderEnabled) await app.setFolderEnabled(true);
      await _loadAccess();
      await app.rebuild();
    } catch (_) {}
  }

  void _addUrl() {
    final u = _url.text.trim();
    if (!u.startsWith('http')) {
      setState(() => _urlError = 'Enter a full link that starts with https');
      return;
    }
    setState(() => _urlError = null);
    app.addManifest(u);
    _url.clear();
    FocusScope.of(context).unfocus();
  }

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return CupertinoListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: CupertinoSwitch(value: value, onChanged: onChanged),
    );
  }

  Widget _segmented(String group, Map<String, String> options, ValueChanged<String> onChanged) {
    return CupertinoListTile(
      title: SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<String>(
          groupValue: group,
          children: <String, Widget>{
            for (final e in options.entries)
              e.key: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                child: Text(e.value),
              ),
          },
          onValueChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final accent = Theme.of(context).colorScheme.primary;
    final bottom = MediaQuery.of(context).padding.bottom;
    final shortPath = app.folderPath.split('/').where((s) => s.isNotEmpty).toList();
    final folderLabel = shortPath.length >= 2
        ? '${shortPath[shortPath.length - 2]}/${shortPath.last}'
        : app.folderPath;

    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => widget.onDragUpdate(d.delta.dy),
            onVerticalDragEnd: (d) => widget.onDragEnd(d.velocity.pixelsPerSecond.dy),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: Sp.x2),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey3.resolveFrom(context),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sources',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                        onPressed: widget.onClose,
                        child: Text('Done', style: TextStyle(color: accent, fontSize: 17)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: bottom + Sp.x6),
              children: [
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Phone folder'),
                  children: [
                    _switchTile('Use phone folder', app.folderEnabled, app.setFolderEnabled,
                        subtitle: '${app.localCount} videos'),
                    CupertinoListTile(
                      leading: Glyph(GlyphKind.folder, size: 22, color: accent),
                      title: const Text('Choose folder'),
                      additionalInfo: Text(folderLabel),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _pickFolder,
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _folder,
                      prefix: const Text('Path'),
                      placeholder: '/storage/emulated/0/Movies',
                      autocorrect: false,
                      onChanged: app.setFolderPath,
                    ),
                    if (!_access)
                      CupertinoListTile(
                        leading: Glyph(GlyphKind.lockOpen, size: 22, color: accent),
                        title: const Text('Allow video access'),
                        subtitle: const Text('Needed to read your phone folder'),
                        trailing: const CupertinoListTileChevron(),
                        onTap: _askAccess,
                      ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Links'),
                  footer: _urlError == null ? null : Text(_urlError!),
                  children: [
                    for (final u in app.manifests)
                      CupertinoListTile(
                        title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => app.removeManifest(u),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Glyph(
                                GlyphKind.minusCircle,
                                size: 22,
                                color: CupertinoColors.systemRed.resolveFrom(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    CupertinoTextFormFieldRow(
                      controller: _url,
                      placeholder: 'Paste a link to videos.json',
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onFieldSubmitted: (_) => _addUrl(),
                    ),
                    CupertinoListTile(
                      title: Text('Add link', style: TextStyle(color: accent)),
                      onTap: _addUrl,
                    ),
                    CupertinoListTile(
                      title: const Text('Refresh now'),
                      subtitle: Text('${app.remoteCount} videos from links'),
                      trailing: app.refreshing
                          ? const CupertinoActivityIndicator()
                          : Glyph(GlyphKind.refresh, size: 22, color: accent),
                      onTap: app.refreshing ? null : () => app.refreshRemote(),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Feed'),
                  children: [
                    _segmented(
                      app.order,
                      const {'newest': 'Newest', 'shuffle': 'Shuffle'},
                      app.setOrder,
                    ),
                    _switchTile('Favorites only', app.favoritesOnly, app.setFavoritesOnly),
                    _switchTile('Play next automatically', app.autoNext, app.setAutoNext,
                        subtitle: 'Off means each video loops'),
                    _switchTile('Share button', app.showShare, app.setShowShare),
                    _switchTile('Haptics', app.haptics, app.setHaptics),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Video fit'),
                  footer: const Text(
                      'Smart fills the screen only when at most 10% would be cropped. Otherwise the whole video is shown.'),
                  children: [
                    _segmented(
                      app.fitPolicy,
                      const {'smart': 'Smart', 'fill': 'Fill', 'fit': 'Fit'},
                      app.setFitPolicy,
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Appearance'),
                  children: [
                    _segmented(
                      app.themeKey,
                      const {'system': 'System', 'light': 'Light', 'dark': 'Dark'},
                      app.setTheme,
                    ),
                    _switchTile('Reduce transparency', app.reduceTransparency,
                        app.setReduceTransparency),
                    _switchTile('Ambient blur', app.ambient, app.setAmbient,
                        subtitle: 'Fills the empty space around wide videos'),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: bg,
                  header: const Text('Offline'),
                  footer: const Text('Your own feed. Your own videos. Nothing else.'),
                  children: [
                    _switchTile('Save videos for offline', app.cacheOffline, app.setCacheOffline,
                        subtitle: 'Link videos stay on this phone after the first play'),
                    CupertinoListTile(
                      title: const Text('Saved videos'),
                      additionalInfo: Text(_cacheBytes == null ? '...' : _size(_cacheBytes!)),
                      trailing: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await CacheService.clear();
                          await _loadCache();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(Sp.x3),
                          child: Text('Clear', style: TextStyle(color: accent)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
