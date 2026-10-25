import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'app_state.dart';
import 'cache.dart';
import 'fit_math.dart';
import 'glass.dart';
import 'glyph.dart';
import 'haptics.dart';
import 'layout_math.dart';
import 'models.dart';
import 'physics.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'zoom.dart';

final Listenable _never = ValueNotifier<int>(0);

/// Watches frame times. If the ambient blur makes scrolling janky, it is
/// switched off automatically.
class AmbientGuard {
  static bool active = false;
  static bool _started = false;
  static int _slow = 0;
  static int _total = 0;

  static void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!active) return;
    for (final t in timings) {
      _total++;
      if (t.totalSpan.inMilliseconds > 24) _slow++;
    }
    if (_total >= 180) {
      if (_slow / _total > 0.35) AppState.instance.throttleAmbient();
      _slow = 0;
      _total = 0;
    }
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _BurstData {
  _BurstData(this.id, this.pos);
  final int id;
  final Offset pos;
}

class _FeedScreenState extends State<FeedScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final AppState app = AppState.instance;
  final PageController _page = PageController(keepPage: false);
  late final ZoomController _zoom = ZoomController(this);
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: Dur.slow,
    reverseDuration: Dur.base,
  );

  final Map<int, VideoPlayerController> _ctrls = <int, VideoPlayerController>{};
  final Set<int> _initializing = <int>{};
  final Set<int> _failed = <int>{};
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final ValueNotifier<bool> _flash = ValueNotifier<bool>(false);
  final List<_BurstData> _bursts = <_BurstData>[];

  VideoPlayerController? _listening;
  Size _screen = Size.zero;
  int _index = 0;
  int _seenVersion = -1;
  String? _currentId;
  int? _pendingSeekMs;
  bool _firstReset = true;

  bool _playing = true;
  bool _scrubbing = false;
  bool _advancing = false;
  bool _hud = true;
  bool _sheetOpen = false;
  bool _zoomedFlag = false;
  bool _multi = false;
  bool _zooming = false;
  int _sheetGen = 0;

  int _pointers = 0;
  Offset _downPos = Offset.zero;
  Duration _downT = Duration.zero;
  bool _moved = false;
  bool _tapPending = false;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapPos = Offset.zero;

  Timer? _hudTimer;
  Timer? _flashTimer;
  Timer? _holdTimer;
  Timer? _tapTimer;
  Timer? _resumeTimer;

  int _lastDecile = -1;
  String _elapsed = '0:00';
  String _remaining = '-0:00';
  int _burstId = 0;

  VideoItem? get _item =>
      (_index >= 0 && _index < app.items.length) ? app.items[_index] : null;

  // ------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.addListener(_onApp);
    _zoom.addListener(_onZoom);
    _zoom.onDetent = (_) => Haptics.selection();
    AmbientGuard.start();
    _showHud();
    _resumeTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveResume());
  }

  @override
  void dispose() {
    _saveResume();
    WidgetsBinding.instance.removeObserver(this);
    app.removeListener(_onApp);
    _zoom.removeListener(_onZoom);
    _hudTimer?.cancel();
    _flashTimer?.cancel();
    _holdTimer?.cancel();
    _tapTimer?.cancel();
    _resumeTimer?.cancel();
    _listening?.removeListener(_tick);
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _progress.dispose();
    _flash.dispose();
    _zoom.dispose();
    _sheet.dispose();
    _page.dispose();
    AmbientGuard.active = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _playCurrent();
    } else if (state == AppLifecycleState.paused) {
      _saveResume();
      for (final c in _ctrls.values) {
        c.pause();
      }
    }
  }

  void _saveResume() {
    final item = _item;
    final c = _ctrls[_index];
    if (item == null || c == null || !c.value.isInitialized) return;
    app.saveResume(item.id, c.value.position.inMilliseconds);
  }

  // --------------------------------------------------------------- state

  void _onApp() {
    if (!mounted) return;
    if (_seenVersion != app.feedVersion) {
      _seenVersion = app.feedVersion;
      _resetFeed();
    }
    _syncZoom();
    setState(() {});
  }

  void _onZoom() {
    final z = _zoom.zoomed;
    if (z != _zoomedFlag && mounted) setState(() => _zoomedFlag = z);
  }

  void _resetFeed() {
    var prevId = _currentId;
    var fromResume = false;
    if (prevId == null && _firstReset) {
      prevId = app.lastId;
      fromResume = true;
    }
    for (final k in _ctrls.keys.toList()) {
      _drop(k);
    }
    _initializing.clear();
    _failed.clear();
    _advancing = false;
    _progress.value = 0;
    _zoom.resetNow();

    final list = app.items;
    var start = 0;
    if (prevId != null) {
      final f = list.indexWhere((v) => v.id == prevId);
      if (f >= 0) {
        start = f;
        if (fromResume && app.lastPosMs > 1000) _pendingSeekMs = app.lastPosMs;
      }
    }
    if (list.isNotEmpty) _firstReset = false;
    _index = start;
    _currentId = list.isEmpty ? null : list[start].id;

    if (start > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _page.hasClients) _page.jumpToPage(start);
      });
    } else if (_page.hasClients) {
      _page.jumpToPage(0);
    }
    for (var k = start - 1; k <= start + 2; k++) {
      _ensure(k);
    }
  }

  // --------------------------------------------------------------- video

  Future<VideoPlayerController> _create(VideoItem item) async {
    if (!item.remote) {
      return VideoPlayerController.file(File(item.uri));
    }
    final cached = await CacheService.cached(item.uri);
    if (cached != null) return VideoPlayerController.file(cached);
    if (app.cacheOffline) {
      CacheService.download(item.uri);
    }
    return VideoPlayerController.networkUrl(Uri.parse(item.uri));
  }

  Future<void> _ensure(int i) async {
    final list = app.items;
    if (i < 0 || i >= list.length) return;
    if (_ctrls.containsKey(i) || _initializing.contains(i) || _failed.contains(i)) {
      return;
    }
    final version = app.feedVersion;
    _initializing.add(i);
    VideoPlayerController? c;
    try {
      c = await _create(list[i]);
      await c.initialize();
      await c.setLooping(!app.autoNext);
      final stale = !mounted ||
          version != app.feedVersion ||
          i < _index - 1 ||
          i > _index + 2;
      if (stale) {
        await c.dispose();
        return;
      }
      if (i == _index && _pendingSeekMs != null) {
        final ms = _pendingSeekMs!;
        _pendingSeekMs = null;
        final total = c.value.duration.inMilliseconds;
        if (ms < total - 1000) await c.seekTo(Duration(milliseconds: ms));
      }
      _ctrls[i] = c;
      if (i == _index) _playCurrent();
      setState(() {});
    } catch (_) {
      await c?.dispose();
      if (mounted && version == app.feedVersion) {
        _failed.add(i);
        if (i == _index) _skipBroken();
        setState(() {});
      }
    } finally {
      _initializing.remove(i);
    }
  }

  void _skipBroken() {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_failed.contains(_index) && _index + 1 < app.items.length) {
        _page.nextPage(duration: Dur.slow, curve: kEase);
      }
    });
  }

  void _drop(int k) {
    final c = _ctrls.remove(k);
    if (c == null) return;
    if (identical(c, _listening)) {
      c.removeListener(_tick);
      _listening = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onPage(int i) {
    if (i == _index) return;
    _saveResume();
    _index = i;
    _currentId = i < app.items.length ? app.items[i].id : null;
    _advancing = false;
    _progress.value = 0;
    _playing = true;
    _zoom.resetNow();

    for (final k in _ctrls.keys.toList()) {
      if (k < i - 1 || k > i + 2) _drop(k);
    }
    for (var k = i - 1; k <= i + 2; k++) {
      _ensure(k);
    }
    _ctrls[i]?.seekTo(Duration.zero);
    _playCurrent();
    _showHud();
    setState(() {});
  }

  void _syncZoom() {
    final c = _ctrls[_index];
    if (c == null || !c.value.isInitialized || _screen.isEmpty) return;
    final fit = FitMath.compute(_screen, c.value.size, policy: app.fitPolicy);
    _zoom.configure(fit, _screen);
    AmbientGuard.active = !fit.fill && app.ambientOn;
  }

  void _playCurrent() {
    for (final e in _ctrls.entries) {
      if (e.key == _index && _playing && !_scrubbing && !_sheetOpen) {
        e.value.setLooping(!app.autoNext);
        e.value.play();
      } else {
        e.value.pause();
      }
    }
    _attach(_ctrls[_index]);
    _syncZoom();
  }

  void _attach(VideoPlayerController? c) {
    if (identical(c, _listening)) return;
    _listening?.removeListener(_tick);
    _listening = c;
    c?.addListener(_tick);
  }

  void _tick() {
    final c = _listening;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized) return;
    final total = v.duration.inMilliseconds;
    if (total <= 0) return;
    final pos = v.position.inMilliseconds;
    if (!_scrubbing) {
      _progress.value = (pos / total).clamp(0.0, 1.0).toDouble();
    }
    if (app.autoNext && !_scrubbing && !_advancing && pos >= total - 150) {
      _advancing = true;
      _next();
    }
  }

  void _next() {
    final c = _ctrls[_index];
    if (_index + 1 >= app.items.length) {
      c?.seekTo(Duration.zero);
      c?.play();
      _advancing = false;
      return;
    }
    if (MediaQuery.of(context).disableAnimations) {
      _page.jumpToPage(_index + 1);
    } else {
      _page.nextPage(duration: Dur.slow, curve: kEase);
    }
  }

  // ----------------------------------------------------------- gestures

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _downPos = e.position;
      _downT = e.timeStamp;
      _moved = false;
      _holdTimer?.cancel();
      _holdTimer = Timer(const Duration(milliseconds: 450), () {
        if (_pointers == 1 && !_moved && !_zoomedFlag && !_scrubbing && !_sheetOpen) {
          _beginScrub(_downPos.dx);
        }
      });
    } else {
      _moved = true;
      _holdTimer?.cancel();
      if (!_multi) setState(() => _multi = true);
    }
    _showHud();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_pointers != 1) return;
    if (!_moved && (e.position - _downPos).distance > 10) {
      _moved = true;
      _holdTimer?.cancel();
    }
    if (_scrubbing) _scrubTo(e.position.dx);
  }

  void _onPointerUp(PointerUpEvent e) {
    final was = _pointers;
    _pointers = math.max(0, _pointers - 1);
    _holdTimer?.cancel();
    if (_pointers == 0 && _multi) setState(() => _multi = false);
    if (_scrubbing) {
      if (_pointers == 0) _endScrub();
      return;
    }
    if (was == 1 &&
        !_moved &&
        !_zooming &&
        (e.timeStamp - _downT) < const Duration(milliseconds: 300)) {
      _registerTap(e.position);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers = math.max(0, _pointers - 1);
    _holdTimer?.cancel();
    if (_pointers == 0 && _multi) setState(() => _multi = false);
    if (_scrubbing && _pointers == 0) _endScrub();
  }

  void _registerTap(Offset pos) {
    final now = DateTime.now();
    if (_tapPending &&
        now.difference(_lastTapAt).inMilliseconds < 300 &&
        (pos - _lastTapPos).distance < 80) {
      _tapTimer?.cancel();
      _tapPending = false;
      _onDoubleTap(pos);
      return;
    }
    _tapPending = true;
    _lastTapAt = now;
    _lastTapPos = pos;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 220), () {
      _tapPending = false;
      _togglePlay();
    });
  }

  void _onDoubleTap(Offset pos) {
    if (_zoom.zoomed) {
      _zoom.reset();
      Haptics.selection();
    } else {
      _like(pos);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2 || _zoom.zoomed) {
      _syncZoom();
      _zooming = true;
      _zoom.start(d.localFocalPoint);
      _holdTimer?.cancel();
      if (_hud) setState(() => _hud = false);
    } else {
      _zooming = false;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_zooming) return;
    if (d.pointerCount < 2 && !_zoom.zoomed) return;
    _zoom.update(d.scale, d.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (!_zooming) return;
    _zooming = false;
    _zoom.end(d.velocity.pixelsPerSecond);
    _showHud();
  }

  // ------------------------------------------------------------ actions

  void _togglePlay() {
    setState(() => _playing = !_playing);
    _playCurrent();
    _flash.value = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 520), () => _flash.value = false);
    _showHud();
  }

  void _like(Offset p) {
    final item = _item;
    if (item == null) return;
    if (!app.isFav(item.id)) app.setFav(item.id, true);
    Haptics.like();
    setState(() => _bursts.add(_BurstData(++_burstId, p)));
    _showHud();
  }

  void _toggleHeart() {
    final item = _item;
    if (item == null) return;
    final now = !app.isFav(item.id);
    app.setFav(item.id, now);
    if (now) {
      Haptics.like();
    } else {
      Haptics.light();
    }
    _showHud();
  }

  Future<void> _share() async {
    final item = _item;
    if (item == null) return;
    Haptics.light();
    try {
      if (!item.remote) {
        await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(item.uri)]));
      } else {
        await SharePlus.instance.share(ShareParams(text: item.uri));
      }
    } catch (_) {}
  }

  void _beginScrub(double dx) {
    final c = _ctrls[_index];
    if (c == null || !c.value.isInitialized) return;
    _scrubbing = true;
    c.pause();
    Haptics.medium();
    _lastDecile = -1;
    _hudTimer?.cancel();
    _scrubTo(dx);
    setState(() {});
  }

  void _scrubTo(double dx) {
    final c = _ctrls[_index];
    if (c == null) return;
    final w = _screen.width;
    final f = ((dx - 24) / (w - 48)).clamp(0.0, 1.0).toDouble();
    final total = c.value.duration;
    final pos = Duration(milliseconds: (total.inMilliseconds * f).round());
    c.seekTo(pos);
    _progress.value = f;
    final decile = (f * 10).floor();
    if (_lastDecile != -1 && decile != _lastDecile) Haptics.selection();
    _lastDecile = decile;
    setState(() {
      _elapsed = _fmt(pos);
      _remaining = '-${_fmt(total - pos)}';
    });
  }

  void _endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    if (_playing && !_sheetOpen) _ctrls[_index]?.play();
    _showHud();
    setState(() {});
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _showHud() {
    _hudTimer?.cancel();
    if (!_hud && mounted) setState(() => _hud = true);
    _hudTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_scrubbing) setState(() => _hud = false);
    });
  }

  // -------------------------------------------------------------- sheet

  void _openSheet() {
    _hudTimer?.cancel();
    setState(() {
      _sheetGen++;
      _sheetOpen = true;
    });
    _playCurrent();
    _sheet.animateTo(1.0, duration: Dur.slow, curve: kEase);
  }

  Future<void> _closeSheet() async {
    await _sheet.animateBack(0.0, duration: Dur.base, curve: kEase);
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    await app.applyChanges();
    if (!mounted) return;
    _playCurrent();
    _showHud();
  }

  void _sheetDrag(double dy, double sheetHeight) {
    _sheet.value = (_sheet.value - dy / sheetHeight).clamp(0.0, 1.0).toDouble();
  }

  void _sheetDragEnd(double velocityY) {
    if (velocityY > 800 || (velocityY.abs() <= 800 && _sheet.value < 0.6)) {
      _closeSheet();
    } else {
      _sheet.animateTo(1.0, duration: Dur.base, curve: kEase);
    }
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pal = Pal.of(context);
    _screen = mq.size;
    final reduce = mq.disableAnimations;
    final sheetTop = mq.padding.top + Sp.x2;
    final sheetHeight = mq.size.height - sheetTop;

    final Widget feedLayer =
        app.items.isEmpty ? _buildEmpty(pal) : _buildFeed(mq, pal, reduce);

    final overlay = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: !_sheetOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _sheetOpen) _closeSheet();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Feed, pushed back while the sheet is open (iOS-style depth).
              AnimatedBuilder(
                animation: _sheet,
                child: feedLayer,
                builder: (context, child) {
                  final v = kEase.transform(_sheet.value);
                  return Transform.scale(
                    scale: reduce ? 1.0 : 1.0 - 0.06 * v,
                    child: ClipRRect(
                      clipBehavior: v == 0 ? Clip.none : Clip.antiAlias,
                      borderRadius: BorderRadius.circular(reduce ? 0 : 22 * v),
                      child: child,
                    ),
                  );
                },
              ),

              // Dim
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _sheet,
                  builder: (context, _) {
                    final v = kEase.transform(_sheet.value);
                    return IgnorePointer(
                      ignoring: v == 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeSheet,
                        child: ColoredBox(
                          color: Colors.black.withAlpha((90 * v).round()),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Sheet
              Positioned.fill(
                top: sheetTop,
                child: AnimatedBuilder(
                  animation: _sheet,
                  builder: (context, _) {
                    final v = kEase.transform(_sheet.value);
                    final sheet = SettingsSheet(
                      key: ValueKey<int>(_sheetGen),
                      onClose: _closeSheet,
                      onDragUpdate: (dy) => _sheetDrag(dy, sheetHeight),
                      onDragEnd: _sheetDragEnd,
                    );
                    return IgnorePointer(
                      ignoring: v == 0,
                      child: reduce
                          ? Opacity(opacity: v, child: sheet)
                          : Transform.translate(
                              offset: Offset(0, (1 - v) * sheetHeight),
                              child: sheet,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(Pal pal) {
    return ColoredBox(
      color: pal.dark ? Colors.black : Colors.white,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: app.loading
                  ? CircularProgressIndicator(color: pal.ink, strokeWidth: 2)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Sp.x8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Your feed is empty',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: pal.ink,
                            ),
                          ),
                          const SizedBox(height: Sp.x2),
                          Text(
                            'Add a phone folder or a link to your videos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: pal.muted, fontSize: 15),
                          ),
                          const SizedBox(height: Sp.x6),
                          FilledButton(
                            onPressed: _openSheet,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(180, 52),
                            ),
                            child: const Text('Open sources'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed(MediaQueryData mq, Pal pal, bool reduce) {
    // The feed is always a dark canvas, like the iOS video player: dark glass,
    // white glyphs, whatever the app appearance is.
    final fp = Pal.darkPal;
    final zones = UiZones.of(mq);
    final chrome = _hud && !_scrubbing && !_zooming && !_sheetOpen;
    final h = mq.size.height;
    final item = _item;
    final fav = item != null && app.isFav(item.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _page,
              physics: (_zoomedFlag || _multi || _scrubbing)
                  ? const NeverScrollableScrollPhysics()
                  : reduce
                      ? const PageScrollPhysics()
                      : const FeedPhysics(parent: BouncingScrollPhysics()),
              itemCount: app.items.length,
              onPageChanged: _onPage,
              itemBuilder: (context, i) {
                final page = RepaintBoundary(
                  child: _VideoPage(
                    controller: _ctrls[i],
                    failed: _failed.contains(i),
                    screen: mq.size,
                    zoom: i == _index ? _zoom : null,
                    ambientOn: app.ambientOn,
                    policy: app.fitPolicy,
                  ),
                );
                return AnimatedBuilder(
                  animation: _page,
                  child: page,
                  builder: (context, child) {
                    final p = (_page.hasClients ? _page.page : null) ?? i.toDouble();
                    final rel = i - p;
                    final ar = rel.abs().clamp(0.0, 1.0).toDouble();
                    if (reduce) {
                      return Opacity(opacity: 1.0 - ar, child: child);
                    }
                    final outgoing = rel <= 0;
                    return Transform.translate(
                      offset: Offset(0, outgoing ? -rel * h * 0.7 : 0),
                      child: Transform.scale(
                        scale: outgoing ? 1.0 - 0.04 * ar : 1.0,
                        child: Opacity(
                          opacity: outgoing ? 1.0 - 0.4 * ar : 1.0,
                          child: child,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),

        // Progress hairline
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _scrubbing ? 0 : 1,
              duration: Dur.fast,
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (context, p, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: p,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(210),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Play / pause indicator
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: _flash,
                builder: (context, on, _) => AnimatedScale(
                  scale: on ? 1 : 0.7,
                  duration: reduce ? Dur.fast : Dur.base,
                  curve: kEase,
                  child: AnimatedOpacity(
                    opacity: on ? 1 : 0,
                    duration: Dur.fast,
                    child: Glass(
                      circle: true,
                      forceDark: true,
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      child: Glyph(
                        _playing ? GlyphKind.play : GlyphKind.pause,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Hearts from double-tap
        for (final b in _bursts)
          Positioned(
            key: ValueKey<int>(b.id),
            left: b.pos.dx - 60,
            top: b.pos.dy - 60,
            width: 120,
            height: 120,
            child: IgnorePointer(
              child: HeartBurst(
                reduce: reduce,
                onDone: () {
                  if (mounted) {
                    setState(() => _bursts.removeWhere((x) => x.id == b.id));
                  }
                },
              ),
            ),
          ),

        // Sources: rarely used, so it lives in the hard-to-reach top corner,
        // inside the top 14% band.
        Positioned(
          top: zones.topOffset,
          right: Sp.x4,
          child: _Reveal(
            visible: chrome,
            delayMs: 0,
            reduce: reduce,
            child: GlassButton(
              glyph: GlyphKind.sliders,
              size: zones.topButton,
              onTap: _openSheet,
            ),
          ),
        ),

        // Share and Like: bottom center, inside the bottom 35% band, the
        // lower edge always above the system inset by 16.
        Positioned(
          left: 0,
          right: 0,
          bottom: zones.bottomOffset,
          child: Center(
            child: _Reveal(
              visible: chrome,
              delayMs: 60,
              reduce: reduce,
              child: AnimatedSize(
                duration: Dur.base,
                curve: kEase,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (app.showShare) ...[
                      GlassButton(
                        glyph: GlyphKind.share,
                        size: zones.bottomButton,
                        onTap: _share,
                      ),
                      const SizedBox(width: Sp.x6),
                    ],
                    _LikeButton(
                      fav: fav,
                      size: zones.bottomButton,
                      onTap: _toggleHeart,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Scrub timeline (replaces the buttons while scrubbing)
        Positioned(
          left: Sp.x4,
          right: Sp.x4,
          bottom: zones.bottomOffset,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _scrubbing ? 1 : 0,
              duration: Dur.base,
              curve: kEase,
              child: AnimatedScale(
                scale: _scrubbing ? 1 : 0.92,
                duration: reduce ? Dur.fast : Dur.base,
                curve: kEase,
                child: Glass(
                  radius: 24,
                  forceDark: true,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.x6 - 4, Sp.x3, Sp.x6 - 4, Sp.x3 + 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_elapsed, style: _timeStyle(fp)),
                          Text(_remaining, style: _timeStyle(fp)),
                        ],
                      ),
                      const SizedBox(height: Sp.x2),
                      ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (context, p, _) => _Track(progress: p, pal: fp),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // New videos toast
        if (app.toast != null)
          Positioned(
            top: zones.topOffset + Sp.x2,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey<String?>(app.toast),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduce ? Dur.fast : Dur.slow,
                  curve: kEase,
                  builder: (context, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, reduce ? 0 : -12 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: Glass(
                    radius: 20,
                    forceDark: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.x4, vertical: Sp.x2 + 2),
                    child: Text(
                      app.toast ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  TextStyle _timeStyle(Pal pal) => TextStyle(
        color: pal.ink.withAlpha(190),
        fontSize: 12,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

// ---------------------------------------------------------------- widgets

class _VideoPage extends StatelessWidget {
  const _VideoPage({
    required this.controller,
    required this.failed,
    required this.screen,
    required this.zoom,
    required this.ambientOn,
    required this.policy,
  });

  final VideoPlayerController? controller;
  final bool failed;
  final Size screen;
  final ZoomController? zoom;
  final bool ambientOn;
  final String policy;

  static const List<Color> _fadeColors = <Color>[
    Color(0xFF000000),
    Color(0xD1000000),
    Color(0x73000000),
    Color(0x00000000),
  ];
  static const List<double> _fadeStops = <double>[0.0, 0.22, 0.58, 1.0];

  Widget _fade({
    double? left,
    double? right,
    double? top,
    double? bottom,
    double? width,
    double? height,
    required Alignment from,
    required Alignment to,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: from,
              end: to,
              colors: _fadeColors,
              stops: _fadeStops,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: failed
            ? const Center(
                child: Text(
                  "Can't play this video",
                  style: TextStyle(color: Color(0x99FFFFFF), fontSize: 15),
                ),
              )
            : null,
      );
    }

    final vs = c.value.size;
    final fit = FitMath.compute(screen, vs, policy: policy);
    final Listenable anim = zoom ?? _never;

    final sharp = SizedBox(
      width: fit.base.width,
      height: fit.base.height,
      child: VideoPlayer(c),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Dur.base,
      curve: kEase,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: ListenableBuilder(
        listenable: anim,
        builder: (context, _) {
          final z = zoom?.z ?? 1.0;
          final tx = zoom?.tx ?? 0.0;
          final ty = zoom?.ty ?? 0.0;
          final dy = fit.dyAt(z);

          // Where the video actually sits right now, and how wide the bars are.
          final vw = fit.base.width * z;
          final vh = fit.base.height * z;
          final cx = screen.width / 2 + tx;
          final cy = screen.height / 2 + ty + dy;
          final top = math.max(0.0, cy - vh / 2);
          final bottom = math.max(0.0, screen.height - (cy + vh / 2));
          final left = math.max(0.0, cx - vw / 2);
          final right = math.max(0.0, screen.width - (cx + vw / 2));
          final hasBars = top > 0.5 || bottom > 0.5 || left > 0.5 || right > 0.5;
          final showAmbient = ambientOn && hasBars;

          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (showAmbient)
                ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 28,
                      sigmaY: 28,
                      tileMode: TileMode.mirror,
                    ),
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: SizedBox(
                        width: vs.width * fit.sFill * 1.15,
                        height: vs.height * fit.sFill * 1.15,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
                ),
              // The blur is strongest next to the video and fades to black at
              // the screen edges.
              if (showAmbient && top > 0.5)
                _fade(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: top,
                  from: Alignment.topCenter,
                  to: Alignment.bottomCenter,
                ),
              if (showAmbient && bottom > 0.5)
                _fade(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: bottom,
                  from: Alignment.bottomCenter,
                  to: Alignment.topCenter,
                ),
              if (showAmbient && left > 0.5)
                _fade(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: left,
                  from: Alignment.centerLeft,
                  to: Alignment.centerRight,
                ),
              if (showAmbient && right > 0.5)
                _fade(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: right,
                  from: Alignment.centerRight,
                  to: Alignment.centerLeft,
                ),
              ClipRect(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(tx, ty + dy)
                    ..scale(z, z, 1.0),
                  child: OverflowBox(
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: sharp,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fades and rises in, one control after another. Fast on the way out.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.visible,
    required this.delayMs,
    required this.reduce,
    required this.child,
  });

  final bool visible;
  final int delayMs;
  final bool reduce;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    final total = 250 + widget.delayMs;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
      reverseDuration: Dur.slow,
      value: widget.visible ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _c,
      curve: Interval(widget.delayMs / total, 1.0, curve: kEase),
      reverseCurve: kEase,
    );
  }

  @override
  void didUpdateWidget(covariant _Reveal old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedBuilder(
        animation: _curved,
        child: widget.child,
        builder: (context, child) {
          final v = _curved.value;
          return Opacity(
            opacity: v.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(0, widget.reduce ? 0 : 8 * (1 - v)),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Like: heart glyph on dark glass. Fills pink with one small bounce.
class _LikeButton extends StatefulWidget {
  const _LikeButton({required this.fav, required this.size, required this.onTap});

  final bool fav;
  final double size;
  final VoidCallback onTap;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  @override
  void didUpdateWidget(covariant _LikeButton old) {
    super.didUpdateWidget(old);
    if (widget.fav && !old.fav && !MediaQuery.of(context).disableAnimations) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fav = widget.fav;
    return Pressable(
      onTap: widget.onTap,
      child: Glass(
        circle: true,
        forceDark: true,
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.scale(
            scale: 1.0 + 0.25 * math.sin(_c.value * math.pi),
            child: child,
          ),
          child: Glyph(
            fav ? GlyphKind.heartFill : GlyphKind.heart,
            size: widget.size * 0.48,
            color: fav ? Pal.pink : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.progress, required this.pal});

  final double progress;
  final Pal pal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final x = (w * progress).clamp(0.0, w).toDouble();
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: pal.ink.withAlpha(60),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: x,
                height: 8,
                decoration: BoxDecoration(
                  color: pal.ink,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Positioned(
                left: math.max(0.0, x - 9),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: const Color(0x33000000), width: 0.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One heart that springs in and floats away. No particles.
/// With reduced motion it simply fades.
class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key, required this.reduce, required this.onDone});

  final bool reduce;
  final VoidCallback onDone;

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: widget.reduce ? Dur.base : const Duration(milliseconds: 700),
    );
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final scale = widget.reduce
            ? 1.0
            : 0.4 + 0.8 * Curves.elasticOut.transform((t / 0.5).clamp(0.0, 1.0).toDouble());
        final opacity =
            t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble();
        final lift = widget.reduce ? 0.0 : -28 * Curves.easeOut.transform(t);
        return Center(
          child: Transform.translate(
            offset: Offset(0, lift),
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: const Glyph(GlyphKind.heartFill, size: 80, color: Pal.pink),
              ),
            ),
          ),
        );
      },
    );
  }
}
