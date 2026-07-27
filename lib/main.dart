// ============================================================
// ThinkUplift V1 — single-file build, v3
// Stories now load live from assets/stories.json in this GitHub repo:
// edit that one file to publish content — no rebuild needed.
// ============================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';


// ═══════════ domain/entities/story.dart ═══════════

/// Core content entity of ThinkUplift.
///
/// A Story is a complete unit of transformation:
/// hook -> real human story -> turning point -> lesson -> action -> reflection.
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.readingMinutes,
    required this.body,
    required this.lifeLesson,
    required this.reflectionQuestions,
    required this.recommendedBooks,
    required this.coverColors,
    this.isTodaysStory = false,
    this.isFeatured = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final int readingMinutes;

  /// Full story text. Paragraphs separated by blank lines.
  /// Lines starting with "## " render as quiet section headings.
  final String body;

  final String lifeLesson;
  final List<String> reflectionQuestions;
  final List<RecommendedBook> recommendedBooks;

  /// Two ARGB ints for the cover gradient (no network images in V1).
  final List<int> coverColors;

  final bool isTodaysStory;
  final bool isFeatured;

  /// Firebase-ready serialization. When a remote StoryRepository is added,
  /// Firestore documents map 1:1 to this entity — the UI layer never changes.
  /// Tolerant parser so non-programmers can write stories in JSON:
  /// coverColors accept '#RRGGBB' strings, body may be a list of
  /// paragraphs, and most fields have sensible defaults.
  factory Story.fromMap(Map<String, dynamic> map) {
    final title = map['title'] as String;
    final body = map['body'] is List
        ? (map['body'] as List).map((e) => e.toString().trim()).join('\n\n')
        : (map['body'] as String);
    final words = body.split(RegExp(r'\s+')).length;
    return Story(
      id: (map['id'] as String?) ??
          title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F]+'), '-'),
      title: title,
      subtitle: map['subtitle'] as String? ?? '',
      category: map['category'] as String? ?? 'Life',
      readingMinutes:
          (map['readingMinutes'] as num?)?.toInt() ?? (words / 170).ceil().clamp(1, 60),
      body: body,
      lifeLesson: map['lifeLesson'] as String? ?? '',
      reflectionQuestions:
          List<String>.from(map['reflectionQuestions'] as List? ?? const []),
      recommendedBooks: (map['recommendedBooks'] as List? ?? const [])
          .map((b) => RecommendedBook.fromMap(Map<String, dynamic>.from(b)))
          .toList(),
      coverColors: (map['coverColors'] as List? ?? const [0xFF3D5A80, 0xFF98C1D9])
          .map(_parseColor)
          .toList(),
      isTodaysStory: map['isTodaysStory'] as bool? ?? false,
      isFeatured: map['isFeatured'] as bool? ?? false,
    );
  }

  static int _parseColor(dynamic v) {
    if (v is int) return v;
    final hex = v.toString().replaceFirst('#', '');
    return 0xFF000000 | int.parse(hex, radix: 16);
  }

  Map<String, dynamic> toMap() => {
        "id": id,
        "title": title,
        "subtitle": subtitle,
        "category": category,
        "readingMinutes": readingMinutes,
        "body": body,
        "lifeLesson": lifeLesson,
        "reflectionQuestions": reflectionQuestions,
        "recommendedBooks": recommendedBooks.map((b) => b.toMap()).toList(),
        "coverColors": coverColors,
        "isTodaysStory": isTodaysStory,
        "isFeatured": isFeatured,
      };
}

class RecommendedBook {
  const RecommendedBook({required this.title, required this.author});

  final String title;
  final String author;

  factory RecommendedBook.fromMap(Map<String, dynamic> map) =>
      RecommendedBook(title: map["title"], author: map["author"]);

  Map<String, dynamic> toMap() => {"title": title, "author": author};
}

// ═══════════ domain/entities/reflection.dart ═══════════

/// A saved journal entry written after finishing a story.
class Reflection {
  const Reflection({
    required this.id,
    required this.storyId,
    required this.storyTitle,
    required this.createdAt,
    required this.touchedMost,
    required this.lessonToApply,
    required this.actionToday,
  });

  final String id;
  final String storyId;
  final String storyTitle;
  final DateTime createdAt;
  final String touchedMost;
  final String lessonToApply;
  final String actionToday;

  factory Reflection.fromMap(Map<String, dynamic> map) => Reflection(
        id: map["id"],
        storyId: map["storyId"],
        storyTitle: map["storyTitle"],
        createdAt: DateTime.parse(map["createdAt"]),
        touchedMost: map["touchedMost"],
        lessonToApply: map["lessonToApply"],
        actionToday: map["actionToday"],
      );

  Map<String, dynamic> toMap() => {
        "id": id,
        "storyId": storyId,
        "storyTitle": storyTitle,
        "createdAt": createdAt.toIso8601String(),
        "touchedMost": touchedMost,
        "lessonToApply": lessonToApply,
        "actionToday": actionToday,
      };
}

// ═══════════ domain/entities/user_stats.dart ═══════════

/// Growth metrics — deliberately NOT engagement metrics.
/// ThinkUplift counts stories completed and reflections written,
/// never screen time or scroll depth.
class UserStats {
  const UserStats({
    required this.storiesRead,
    required this.reflectionCount,
    required this.readingStreak,
    required this.bookmarkCount,
  });

  final int storiesRead;
  final int reflectionCount;
  final int readingStreak;
  final int bookmarkCount;
}

// ═══════════ domain/repositories/story_repository.dart ═══════════

/// Contract for story content.
///
/// V1 ships [LocalStoryRepository] (bundled demo stories). Later, a
/// FirebaseStoryRepository can implement this same interface and be swapped
/// in via the Riverpod provider — zero UI changes required.
abstract class StoryRepository {
  Future<List<Story>> getAllStories();
  Future<Story?> getStoryById(String id);
  Future<List<String>> getCategories();
}

// ═══════════ domain/repositories/reflection_repository.dart ═══════════

abstract class ReflectionRepository {
  Future<List<Reflection>> getReflections();
  Future<void> saveReflection(Reflection reflection);
}

// ═══════════ domain/repositories/progress_repository.dart ═══════════

/// Tracks personal reading state: progress, completion, bookmarks, streak.
/// Local in V1; the same contract can back a synced Firestore implementation.
abstract class ProgressRepository {
  Future<double> getProgress(String storyId);
  Future<void> saveProgress(String storyId, double progress);

  /// The story most recently opened but not finished ("Continue Reading").
  Future<String?> getContinueReadingId();
  Future<void> setContinueReadingId(String? storyId);

  Future<Set<String>> getCompletedStoryIds();
  Future<void> markCompleted(String storyId);

  Future<Set<String>> getBookmarkedIds();
  Future<void> toggleBookmark(String storyId);

  /// Records today as a reading day and returns the current streak.
  Future<int> recordReadingDay();
  Future<int> getStreak();
}

// ═══════════ data/demo/demo_stories.dart ═══════════

// Demo stories have been retired. All content now lives in
// assets/stories.json, editable on GitHub without rebuilding the app.

// ═══════════ data/local/local_store.dart ═══════════

/// Thin typed wrapper over SharedPreferences.
/// Keeps all storage keys in one place so a future migration
/// (e.g. to Firestore-backed sync) touches exactly one file.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kProgressPrefix = "progress_";
  static const _kContinueReading = "continue_reading_id";
  static const _kCompleted = "completed_story_ids";
  static const _kBookmarks = "bookmarked_story_ids";
  static const _kReadingDays = "reading_days"; // list of yyyy-MM-dd
  static const _kReflections = "reflections_json";
  static const _kThemeMode = "theme_mode"; // system | light | dark
  static const _kFontScale = "reader_font_scale";

  static Future<LocalStore> init() async =>
      LocalStore(await SharedPreferences.getInstance());

  // --- Reading progress ---
  double getProgress(String storyId) =>
      _prefs.getDouble("$_kProgressPrefix$storyId") ?? 0;

  Future<void> setProgress(String storyId, double value) =>
      _prefs.setDouble("$_kProgressPrefix$storyId", value.clamp(0, 1));

  String? getContinueReadingId() => _prefs.getString(_kContinueReading);

  Future<void> setContinueReadingId(String? id) => id == null
      ? _prefs.remove(_kContinueReading)
      : _prefs.setString(_kContinueReading, id);

  // --- Completion ---
  Set<String> getCompleted() =>
      (_prefs.getStringList(_kCompleted) ?? const []).toSet();

  Future<void> addCompleted(String id) =>
      _prefs.setStringList(_kCompleted, {...getCompleted(), id}.toList());

  // --- Bookmarks ---
  Set<String> getBookmarks() =>
      (_prefs.getStringList(_kBookmarks) ?? const []).toSet();

  Future<void> setBookmarks(Set<String> ids) =>
      _prefs.setStringList(_kBookmarks, ids.toList());

  // --- Streak ---
  List<String> getReadingDays() => _prefs.getStringList(_kReadingDays) ?? [];

  Future<void> setReadingDays(List<String> days) =>
      _prefs.setStringList(_kReadingDays, days);

  // --- Reflections ---
  List<Map<String, dynamic>> getReflections() {
    final raw = _prefs.getString(_kReflections);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> setReflections(List<Map<String, dynamic>> items) =>
      _prefs.setString(_kReflections, jsonEncode(items));

  // --- Settings ---
  String getThemeMode() => _prefs.getString(_kThemeMode) ?? "system";
  Future<void> setThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

  String? getCachedStoriesJson() => _prefs.getString(_kStoriesCache);
  Future<void> setCachedStoriesJson(String json) =>
      _prefs.setString(_kStoriesCache, json);

  double getFontScale() => _prefs.getDouble(_kFontScale) ?? 1.0;
  Future<void> setFontScale(double scale) =>
      _prefs.setDouble(_kFontScale, scale);
}

// ═══════════ data/repositories/local_story_repository.dart ═══════════

/// Stories live in assets/stories.json — one file the writer edits on
/// GitHub. On launch the app fetches the latest version of that file from
/// the repo, so new and edited stories appear WITHOUT rebuilding the APK.
///
/// Load order: remote file -> last successful copy (offline) -> bundled copy.
/// A broken edit (invalid JSON) never crashes the app; it silently falls
/// back to the previous good version.
class JsonStoryRepository implements StoryRepository {
  JsonStoryRepository(this._store);

  final LocalStore _store;

  static const _remoteUrl =
      "https://raw.githubusercontent.com/thinkupliftmag-a11y/ThinkUplift/main/assets/stories.json";

  List<Story>? _stories;
  List<String>? _categories;

  Future<void> _ensureLoaded() async {
    if (_stories != null) return;

    final remote = await _fetchRemote();
    if (remote != null && _tryParse(remote)) {
      await _store.setCachedStoriesJson(remote);
      return;
    }
    final cached = _store.getCachedStoriesJson();
    if (cached != null && _tryParse(cached)) return;

    _tryParse(await rootBundle.loadString("assets/stories.json"));
    _stories ??= const [];
    _categories ??= const [];
  }

  bool _tryParse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final stories = (map["stories"] as List)
          .map((e) => Story.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (stories.isEmpty) return false;
      _stories = stories;
      _categories = List<String>.from(map["categories"] as List? ?? const [])
          .isNotEmpty
          ? List<String>.from(map["categories"] as List)
          : stories.map((s) => s.category).toSet().toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _fetchRemote() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final request = await client.getUrl(Uri.parse(_remoteUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return null; // offline or blocked — fall back gracefully
    }
  }

  @override
  Future<List<Story>> getAllStories() async {
    await _ensureLoaded();
    return _stories!;
  }

  @override
  Future<Story?> getStoryById(String id) async {
    await _ensureLoaded();
    for (final s in _stories!) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<String>> getCategories() async {
    await _ensureLoaded();
    return _categories!;
  }
}

// ═══════════ data/repositories/local_reflection_repository.dart ═══════════

class LocalReflectionRepository implements ReflectionRepository {
  LocalReflectionRepository(this._store);

  final LocalStore _store;

  @override
  Future<List<Reflection>> getReflections() async {
    final list = _store.getReflections().map(Reflection.fromMap).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> saveReflection(Reflection reflection) async {
    final items = _store.getReflections()..add(reflection.toMap());
    await _store.setReflections(items);
  }
}

// ═══════════ data/repositories/local_progress_repository.dart ═══════════

class LocalProgressRepository implements ProgressRepository {
  LocalProgressRepository(this._store);

  final LocalStore _store;

  static String _dayKey(DateTime d) =>
      "${d.year.toString().padLeft(4, "0")}-"
      "${d.month.toString().padLeft(2, "0")}-"
      "${d.day.toString().padLeft(2, "0")}";

  @override
  Future<double> getProgress(String storyId) async =>
      _store.getProgress(storyId);

  @override
  Future<void> saveProgress(String storyId, double progress) =>
      _store.setProgress(storyId, progress);

  @override
  Future<String?> getContinueReadingId() async =>
      _store.getContinueReadingId();

  @override
  Future<void> setContinueReadingId(String? storyId) =>
      _store.setContinueReadingId(storyId);

  @override
  Future<Set<String>> getCompletedStoryIds() async => _store.getCompleted();

  @override
  Future<void> markCompleted(String storyId) => _store.addCompleted(storyId);

  @override
  Future<Set<String>> getBookmarkedIds() async => _store.getBookmarks();

  @override
  Future<void> toggleBookmark(String storyId) async {
    final marks = _store.getBookmarks();
    marks.contains(storyId) ? marks.remove(storyId) : marks.add(storyId);
    await _store.setBookmarks(marks);
  }

  @override
  Future<int> recordReadingDay() async {
    final days = _store.getReadingDays().toSet()
      ..add(_dayKey(DateTime.now()));
    await _store.setReadingDays(days.toList()..sort());
    return getStreak();
  }

  @override
  Future<int> getStreak() async {
    final days = _store.getReadingDays().toSet();
    if (days.isEmpty) return 0;

    var streak = 0;
    var cursor = DateTime.now();

    // A streak survives if today has not been read yet but yesterday was.
    if (!days.contains(_dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(_dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

// ═══════════ providers/app_providers.dart ═══════════

/// Initialized in main() before runApp.
final localStoreProvider =
    Provider<LocalStore>((ref) => throw UnimplementedError());

// ---------- Repository seams (swap these to go remote/Firebase) ----------
final storyRepositoryProvider = Provider<StoryRepository>(
    (ref) => JsonStoryRepository(ref.watch(localStoreProvider)));

final reflectionRepositoryProvider = Provider<ReflectionRepository>(
    (ref) => LocalReflectionRepository(ref.watch(localStoreProvider)));

final progressRepositoryProvider = Provider<ProgressRepository>(
    (ref) => LocalProgressRepository(ref.watch(localStoreProvider)));

// ---------- Content ----------
final storiesProvider = FutureProvider<List<Story>>(
    (ref) => ref.watch(storyRepositoryProvider).getAllStories());

final categoriesProvider = FutureProvider<List<String>>(
    (ref) => ref.watch(storyRepositoryProvider).getCategories());

final storyByIdProvider = FutureProvider.family<Story?, String>(
    (ref, id) => ref.watch(storyRepositoryProvider).getStoryById(id));

// ---------- Personal state ----------
class ReadingStateNotifier extends Notifier<ReadingState> {
  @override
  ReadingState build() {
    final store = ref.watch(localStoreProvider);
    return ReadingState(
      bookmarks: store.getBookmarks(),
      completed: store.getCompleted(),
      continueReadingId: store.getContinueReadingId(),
    );
  }

  ProgressRepository get _repo => ref.read(progressRepositoryProvider);

  Future<void> toggleBookmark(String storyId) async {
    await _repo.toggleBookmark(storyId);
    state = state.copyWith(bookmarks: await _repo.getBookmarkedIds());
  }

  Future<void> openedStory(String storyId) async {
    if (!state.completed.contains(storyId)) {
      await _repo.setContinueReadingId(storyId);
      state = state.copyWith(continueReadingId: storyId);
    }
  }

  Future<void> saveProgress(String storyId, double progress) =>
      _repo.saveProgress(storyId, progress);

  Future<void> completedStory(String storyId) async {
    await _repo.markCompleted(storyId);
    await _repo.recordReadingDay();
    if (state.continueReadingId == storyId) {
      await _repo.setContinueReadingId(null);
    }
    state = state.copyWith(
      completed: await _repo.getCompletedStoryIds(),
      continueReadingId:
          state.continueReadingId == storyId ? null : state.continueReadingId,
      clearContinue: state.continueReadingId == storyId,
    );
    ref.invalidate(userStatsProvider);
  }
}

class ReadingState {
  const ReadingState({
    required this.bookmarks,
    required this.completed,
    required this.continueReadingId,
  });

  final Set<String> bookmarks;
  final Set<String> completed;
  final String? continueReadingId;

  ReadingState copyWith({
    Set<String>? bookmarks,
    Set<String>? completed,
    String? continueReadingId,
    bool clearContinue = false,
  }) =>
      ReadingState(
        bookmarks: bookmarks ?? this.bookmarks,
        completed: completed ?? this.completed,
        continueReadingId: clearContinue
            ? null
            : (continueReadingId ?? this.continueReadingId),
      );
}

final readingStateProvider =
    NotifierProvider<ReadingStateNotifier, ReadingState>(
        ReadingStateNotifier.new);

// ---------- Reflections ----------
class ReflectionsNotifier extends AsyncNotifier<List<Reflection>> {
  @override
  Future<List<Reflection>> build() =>
      ref.watch(reflectionRepositoryProvider).getReflections();

  Future<void> save(Reflection reflection) async {
    await ref.read(reflectionRepositoryProvider).saveReflection(reflection);
    state = AsyncData(
        await ref.read(reflectionRepositoryProvider).getReflections());
    ref.invalidate(userStatsProvider);
  }
}

final reflectionsProvider =
    AsyncNotifierProvider<ReflectionsNotifier, List<Reflection>>(
        ReflectionsNotifier.new);

// ---------- Stats (growth metrics, not engagement metrics) ----------
final userStatsProvider = FutureProvider<UserStats>((ref) async {
  final progress = ref.watch(progressRepositoryProvider);
  final reading = ref.watch(readingStateProvider);
  final reflections = await ref.watch(reflectionsProvider.future);
  return UserStats(
    storiesRead: reading.completed.length,
    reflectionCount: reflections.length,
    readingStreak: await progress.getStreak(),
    bookmarkCount: reading.bookmarks.length,
  );
});

// ---------- Settings ----------
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    switch (ref.watch(localStoreProvider).getThemeMode()) {
      case "light":
        return ThemeMode.light;
      case "dark":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(localStoreProvider).setThemeMode(mode.name);
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class FontScaleNotifier extends Notifier<double> {
  @override
  double build() => ref.watch(localStoreProvider).getFontScale();

  Future<void> set(double scale) async {
    final clamped = scale.clamp(0.85, 1.4);
    await ref.read(localStoreProvider).setFontScale(clamped);
    state = clamped;
  }
}

final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, double>(FontScaleNotifier.new);

// ═══════════ core/theme/app_theme.dart ═══════════

/// ThinkUplift design language.
///
/// Principle: "Does this create noise or clarity?" — always clarity.
///
/// Tokens:
///  · Paper white background (#FFFFFF light / #12161C dark)
///  · One accent: soft blue (ink blue #3E5C8F light / powder blue dark)
///  · Display face: Fraunces — warm, bookish serif for titles
///  · Reading face: Lora — long-form serif, Kindle-calm
///  · Utility face: Inter — quiet UI labels
class AppColors {
  // Light
  static const paper = Color(0xFFFFFFFF);
  static const softSurface = Color(0xFFF6F8FB);
  static const ink = Color(0xFF1C2430);
  static const inkMuted = Color(0xFF66707E);
  static const accent = Color(0xFF3E5C8F); // soft ink blue
  static const accentSoft = Color(0xFFE8EEF7);
  static const hairline = Color(0xFFE6EAF0);

  // Dark — warm charcoal, never pure black, easy on night eyes
  static const paperDark = Color(0xFF12161C);
  static const softSurfaceDark = Color(0xFF1A2029);
  static const inkDark = Color(0xFFE7EAEF);
  static const inkMutedDark = Color(0xFF939CA9);
  static const accentDark = Color(0xFF9DB8E3); // powder blue
  static const accentSoftDark = Color(0xFF243247);
  static const hairlineDark = Color(0xFF262E3A);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;

    final paper = isDark ? AppColors.paperDark : AppColors.paper;
    final surface = isDark ? AppColors.softSurfaceDark : AppColors.softSurface;
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final muted = isDark ? AppColors.inkMutedDark : AppColors.inkMuted;
    final accent = isDark ? AppColors.accentDark : AppColors.accent;
    final accentSoft =
        isDark ? AppColors.accentSoftDark : AppColors.accentSoft;
    final hairline = isDark ? AppColors.hairlineDark : AppColors.hairline;

    final scheme = ColorScheme(
      brightness: b,
      primary: accent,
      onPrimary: isDark ? AppColors.paperDark : Colors.white,
      primaryContainer: accentSoft,
      onPrimaryContainer: isDark ? AppColors.accentDark : AppColors.accent,
      secondary: accent,
      onSecondary: isDark ? AppColors.paperDark : Colors.white,
      surface: paper,
      onSurface: ink,
      surfaceContainerHighest: surface,
      surfaceContainerHigh: surface,
      surfaceContainer: surface,
      onSurfaceVariant: muted,
      outline: hairline,
      outlineVariant: hairline,
      error: const Color(0xFFB3574E),
      onError: Colors.white,
      shadow: Colors.black.withValues(alpha: 0.06),
      scrim: Colors.black54,
      inverseSurface: ink,
      onInverseSurface: paper,
      inversePrimary: accentSoft,
      tertiary: accent,
      onTertiary: Colors.white,
    );

    final display = GoogleFonts.fraunces(color: ink);
    final body = GoogleFonts.lora(color: ink, height: 1.7);
    final ui = GoogleFonts.inter(color: ink);

    final textTheme = TextTheme(
      // Display — story titles, greeting
      displaySmall: display.copyWith(
          fontSize: 34, fontWeight: FontWeight.w600, height: 1.2),
      headlineMedium: display.copyWith(
          fontSize: 26, fontWeight: FontWeight.w600, height: 1.25),
      headlineSmall: display.copyWith(
          fontSize: 21, fontWeight: FontWeight.w600, height: 1.3),
      titleLarge: display.copyWith(
          fontSize: 18, fontWeight: FontWeight.w600, height: 1.35),
      // Reading body
      bodyLarge: body.copyWith(fontSize: 18),
      bodyMedium: body.copyWith(fontSize: 15, color: muted, height: 1.6),
      // UI
      titleMedium: ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: ui.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelLarge: ui.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: ui.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: muted),
      bodySmall: ui.copyWith(fontSize: 12.5, color: muted, height: 1.4),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: ink, size: 22),
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? AppColors.paperDark : Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: hairline),
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: accent, textStyle: textTheme.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        hintStyle: body.copyWith(fontSize: 15, color: muted),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: hairline,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.1),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(paper),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : hairline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: ui.copyWith(color: paper, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // Calm, consistent transitions on both platforms.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}

// ═══════════ core/router/app_router.dart ═══════════

/// Route names — future screens (AI Mentor, Library, Audio) slot in here
/// without touching existing screens.
abstract class Routes {
  static const splash = "/";
  static const home = "/home";
  static const reader = "/story/:id";
  static const reflection = "/story/:id/reflect";
  static const profile = "/profile";

  static String readerPath(String id) => "/story/$id";
  static String reflectionPath(String id) => "/story/$id/reflect";
}

/// A gentle fade + slight upward drift. No bounce, no flash.
CustomTransitionPage<void> _calmPage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
                    begin: const Offset(0, 0.015), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );

final appRouter = GoRouter(
  initialLocation: Routes.splash,
  routes: [
    GoRoute(
      path: Routes.splash,
      pageBuilder: (c, s) => _calmPage(s, const SplashScreen()),
    ),
    GoRoute(
      path: Routes.home,
      pageBuilder: (c, s) => _calmPage(s, const HomeScreen()),
      routes: [
        GoRoute(
          path: "profile",
          pageBuilder: (c, s) => _calmPage(s, const ProfileScreen()),
        ),
      ],
    ),
    GoRoute(
      path: Routes.reader,
      pageBuilder: (c, s) =>
          _calmPage(s, ReaderScreen(storyId: s.pathParameters["id"]!)),
      routes: [
        GoRoute(
          path: "reflect",
          pageBuilder: (c, s) =>
              _calmPage(s, ReflectionScreen(storyId: s.pathParameters["id"]!)),
        ),
      ],
    ),
  ],
);

// ═══════════ features/shared/widgets.dart ═══════════

/// Cover art for a story: a calm two-tone gradient with a large,
/// low-opacity serif initial — like an embossed book cover.
/// No network images in V1; covers are generated, consistent, and quiet.
class StoryCover extends StatelessWidget {
  const StoryCover({
    super.key,
    required this.story,
    this.borderRadius = 16,
    this.initialSize = 64,
  });

  final Story story;
  final double borderRadius;
  final double initialSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(story.coverColors[0]),
              Color(story.coverColors[1]),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -initialSize * 0.15,
              bottom: -initialSize * 0.3,
              child: Text(
                story.title.characters.first,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: initialSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.18),
                  height: 1,
                ),
              ),
            ),
            const Positioned.fill(child: SizedBox()),
          ],
        ),
      ),
    );
  }
}

class CategoryTag extends StatelessWidget {
  const CategoryTag(this.label, {super.key, this.onDark = false});

  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: onDark
            ? Colors.white.withValues(alpha: 0.85)
            : theme.colorScheme.primary,
      ),
    );
  }
}

class MetaDot extends StatelessWidget {
  const MetaDot({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// Wide card used for Today's Story and featured stories.
class FeaturedStoryCard extends StatelessWidget {
  const FeaturedStoryCard({super.key, required this.story, this.onTap});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
                height: 130,
                child: StoryCover(
                    story: story, borderRadius: 0, initialSize: 120)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryTag(story.category),
                  const SizedBox(height: 6),
                  Text(story.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    story.subtitle,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text('${story.readingMinutes} min read',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row card used in Recent Stories and bookmark lists.
class StoryRowCard extends StatelessWidget {
  const StoryRowCard({
    super.key,
    required this.story,
    this.onTap,
    this.trailing,
    this.progress,
  });

  final Story story;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                  width: 64,
                  height: 64,
                  child: StoryCover(story: story, initialSize: 46)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(story.category,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary)),
                        const MetaDot(),
                        Text('${story.readingMinutes} min',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    if (progress != null && progress! > 0.02) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading used across Home and Profile.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        child:
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
      );
}

// ═══════════ features/home/widgets/soft_card.dart ═══════════

/// The Home Screen surface: rounded 20px, a whisper of shadow in light mode
/// (like a card resting on paper), flat tonal surface in dark mode where
/// shadows would read as noise.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ═══════════ features/home/widgets/fade_in_section.dart ═══════════

/// Sections fade in once with a 10px drift, lightly staggered by [order].
/// Runs a single time on first build; honors "reduce motion".
/// This is the only entrance animation on the Home Screen — one calm
/// orchestrated moment instead of scattered effects.
class FadeInSection extends StatefulWidget {
  const FadeInSection({super.key, required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<FadeInSection> createState() => _FadeInSectionState();
}

class _FadeInSectionState extends State<FadeInSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  late final CurvedAnimation _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.reduceMotion;
    if (reduceMotion) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: 60 * widget.order), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(
              offset: Offset(0, 10 * (1 - _a.value)), child: child),
        ),
        child: widget.child,
      );
}

// ═══════════ features/home/widgets/greeting_header.dart ═══════════

/// A quiet welcome: time-of-day greeting in the display serif,
/// one soft line beneath it, a single unobtrusive profile action.
/// No avatar bubbles, no notification bells, no badges.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.onProfileTap});

  final VoidCallback onProfileTap;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return "A quiet hour";
    if (h < 12) return "Good morning";
    if (h < 17) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: theme.textTheme.displaySmall),
                const SizedBox(height: 6),
                Text("What will you learn today?",
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: "Your journey",
            icon: const Icon(Icons.person_outline),
            onPressed: onProfileTap,
          ),
        ],
      ),
    );
  }
}

// ═══════════ features/home/widgets/continue_reading_card.dart ═══════════

/// The last opened story, with a hairline progress bar and how far
/// the reader has come — a bookmark ribbon, not a nag.
class ContinueReadingCard extends ConsumerWidget {
  const ContinueReadingCard({super.key, required this.story, this.onTap});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return FutureBuilder<double>(
      future: ref.read(progressRepositoryProvider).getProgress(story.id),
      builder: (context, snap) {
        final progress = (snap.data ?? 0).clamp(0.0, 1.0);
        final minutesLeft =
            (story.readingMinutes * (1 - progress)).ceil().clamp(1, 99);
        return SoftCard(
          onTap: onTap,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: StoryCover(story: story, initialSize: 48),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(story.title,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      progress > 0.02
                          ? "About $minutesLeft min left"
                          : "${story.readingMinutes} min read",
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.play_arrow_rounded,
                  size: 24, color: theme.colorScheme.primary),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════ features/home/widgets/todays_story_card.dart ═══════════

/// The single hero of the Home Screen: one large card, one story,
/// chosen for today. Tall cover, serif title, subtitle, reading time.
class TodaysStoryCard extends StatelessWidget {
  const TodaysStoryCard({super.key, required this.story, this.onTap});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoryCover(story: story, borderRadius: 0, initialSize: 140),
                Positioned(
                  left: 18,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const CategoryTag("Today\u2019s story",
                        onDark: true),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(story.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  story.subtitle,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(story.category,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const MetaDot(),
                    Text("${story.readingMinutes} min read",
                        style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Text("Read",
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: theme.colorScheme.primary),
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

// ═══════════ features/home/widgets/featured_story_card.dart ═══════════

/// Compact card for the horizontal Featured rail.
/// Fixed 260px width; the rail scrolls with gentle bouncing physics.
class FeaturedStoryRailCard extends StatelessWidget {
  const FeaturedStoryRailCard({super.key, required this.story, this.onTap});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: SoftCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 100,
              child:
                  StoryCover(story: story, borderRadius: 0, initialSize: 84),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryTag(story.category),
                  const SizedBox(height: 5),
                  Text(story.title,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text("${story.readingMinutes} min read",
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════ features/home/widgets/category_chips.dart ═══════════

/// A single quiet row of pills. Selecting one filters the list below;
/// tapping it again clears the filter. No badges, no counts, no icons.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final isSelected = c == selected;
          return ChoiceChip(
            label: Text(c),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onSelected(isSelected ? null : c),
            labelStyle: theme.textTheme.titleSmall?.copyWith(
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            side: BorderSide.none,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        },
      ),
    );
  }
}

// ═══════════ features/home/widgets/recent_story_tile.dart ═══════════

/// One story per row: cover, title, category, minutes.
/// A small check marks stories already finished — quiet proof of progress.
class RecentStoryTile extends StatelessWidget {
  const RecentStoryTile({
    super.key,
    required this.story,
    this.onTap,
    this.isCompleted = false,
  });

  final Story story;
  final VoidCallback? onTap;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: StoryCover(story: story, initialSize: 46),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(story.title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(story.category,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const MetaDot(),
                    Text("${story.readingMinutes} min",
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          if (isCompleted) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle_outline,
                size: 20, color: theme.colorScheme.primary),
          ],
        ],
      ),
    );
  }
}

// ═══════════ features/splash/splash_screen.dart ═══════════

/// A quiet arrival: the wordmark breathes in, the tagline follows,
/// a hairline underline draws itself. Then the app opens.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoRise;
  late final Animation<double> _line;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));

    _logoFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.4, curve: Curves.easeOut));
    _logoRise = Tween(begin: 12.0, end: 0.0).animate(CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic)));
    _line = CurvedAnimation(
        parent: _c, curve: const Interval(0.35, 0.65, curve: Curves.easeInOut));
    _taglineFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.55, 0.9, curve: Curves.easeOut));

    _start();
  }

  Future<void> _start() async {
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .reduceMotion;
    if (reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    await Future.delayed(const Duration(milliseconds: 2200));
    if (mounted) context.go(Routes.home);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: _logoFade.value,
                child: Transform.translate(
                  offset: Offset(0, _logoRise.value),
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.displaySmall,
                      children: [
                        const TextSpan(text: 'Think'),
                        TextSpan(
                          text: 'Uplift',
                          style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Hairline that draws itself — a bookmark ribbon settling.
              SizedBox(
                width: 120,
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 1.5,
                    width: 120 * _line.value,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Opacity(
                opacity: _taglineFade.value,
                child: Text(
                  'Read  •  Reflect  •  Rebuild',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(letterSpacing: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════ features/home/home_screen.dart ═══════════

/// The Home Screen of ThinkUplift.
///
/// A single calm scroll — closer to a table of contents than a feed:
/// greeting → continue reading → today's story → featured rail →
/// categories → recent stories. Sections fade in once, gently staggered.
/// Content is capped at a 720px measure so tablets read like a book page,
/// not a stretched phone.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;

  void _openStory(Story story) {
    ref.read(readingStateProvider.notifier).openedStory(story.id);
    context.push(Routes.readerPath(story.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storiesAsync = ref.watch(storiesProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final reading = ref.watch(readingStateProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: storiesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Stories could not be loaded. Close and reopen the app.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (stories) {
            final todays =
                stories.where((s) => s.isTodaysStory).firstOrNull ??
                    stories.first;
            final featured = stories
                .where((s) => s.isFeatured && s.id != todays.id)
                .toList();
            final recent = _selectedCategory == null
                ? stories
                : stories
                    .where((s) => s.category == _selectedCategory)
                    .toList();
            final continueStory = reading.continueReadingId == null
                ? null
                : stories
                    .where((s) => s.id == reading.continueReadingId)
                    .firstOrNull;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // ---- 1. Greeting ----
                    SliverToBoxAdapter(
                      child: FadeInSection(
                        order: 0,
                        child: GreetingHeader(
                          onProfileTap: () => context.push('/home/profile'),
                        ),
                      ),
                    ),

                    // ---- 2. Continue Reading ----
                    if (continueStory != null)
                      SliverToBoxAdapter(
                        child: FadeInSection(
                          order: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeading('Continue reading'),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                child: ContinueReadingCard(
                                  story: continueStory,
                                  onTap: () => _openStory(continueStory),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ---- 3. Today's Story ----
                    SliverToBoxAdapter(
                      child: FadeInSection(
                        order: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeading("Today's story"),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: TodaysStoryCard(
                                story: todays,
                                onTap: () => _openStory(todays),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---- 4. Featured rail ----
                    if (featured.isNotEmpty)
                      SliverToBoxAdapter(
                        child: FadeInSection(
                          order: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeading('Featured stories'),
                              SizedBox(
                                height: 208,
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: featured.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 14),
                                  itemBuilder: (context, i) =>
                                      FeaturedStoryRailCard(
                                    story: featured[i],
                                    onTap: () => _openStory(featured[i]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ---- 5. Categories ----
                    SliverToBoxAdapter(
                      child: FadeInSection(
                        order: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeading('Categories'),
                            categoriesAsync.when(
                              loading: () => const SizedBox(height: 40),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (categories) => CategoryChips(
                                categories: categories,
                                selected: _selectedCategory,
                                onSelected: (c) =>
                                    setState(() => _selectedCategory = c),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---- 6. Recent stories ----
                    SliverToBoxAdapter(
                      child: FadeInSection(
                        order: 5,
                        child: SectionHeading(_selectedCategory == null
                            ? 'Recent stories'
                            : _selectedCategory!),
                      ),
                    ),
                    if (recent.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'No stories here yet. New stories arrive with each update.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: recent.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final story = recent[i];
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: FadeInSection(
                              order: 6,
                              child: RecentStoryTile(
                                story: story,
                                isCompleted:
                                    reading.completed.contains(story.id),
                                onTap: () => _openStory(story),
                              ),
                            ),
                          );
                        },
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 48)),
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

// ═══════════ features/reader/reader_screen.dart ═══════════

/// The heart of ThinkUplift: a page that reads like a well-set book.
/// Generous margins, serif body, a hairline progress ribbon —
/// and nothing else competing for attention.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.storyId});

  final String storyId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _scroll = ScrollController();
  double _progress = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final max = _scroll.position.maxScrollExtent;
    final p = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((p - _progress).abs() > 0.01) {
      setState(() => _progress = p);
      ref
          .read(readingStateProvider.notifier)
          .saveProgress(widget.storyId, p);
    }
    if (p > 0.985 && !_completed) {
      _completed = true;
      ref.read(readingStateProvider.notifier).completedStory(widget.storyId);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _showFontSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final scale = ref.watch(fontScaleProvider);
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Text size', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('A',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontSize: 14)),
                    Expanded(
                      child: Slider(
                        value: scale,
                        min: 0.85,
                        max: 1.4,
                        divisions: 11,
                        onChanged: (v) =>
                            ref.read(fontScaleProvider.notifier).set(v),
                      ),
                    ),
                    Text('A',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontSize: 24)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storyAsync = ref.watch(storyByIdProvider(widget.storyId));
    final reading = ref.watch(readingStateProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return storyAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('This story could not be opened.'))),
      data: (story) {
        if (story == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Story not found.')));
        }
        final bookmarked = reading.bookmarks.contains(story.id);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                tooltip: 'Text size',
                icon: const Icon(Icons.text_fields_rounded),
                onPressed: _showFontSheet,
              ),
              IconButton(
                tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded),
                color: bookmarked ? theme.colorScheme.primary : null,
                onPressed: () => ref
                    .read(readingStateProvider.notifier)
                    .toggleBookmark(story.id),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                      text:
                          '"${story.title}" — a story worth sitting with, on ThinkUplift.\n\n${story.lifeLesson}'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Story copied — paste it anywhere to share.')));
                  }
                },
              ),
              const SizedBox(width: 4),
            ],
            // Reading progress: a quiet hairline ribbon under the bar.
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
          body: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  // Book-page measure on tablets and large phones.
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CategoryTag(story.category),
                        const SizedBox(height: 10),
                        Text(story.title,
                            style: theme.textTheme.displaySmall),
                        const SizedBox(height: 10),
                        Text(story.subtitle,
                            style: theme.textTheme.bodyLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                color:
                                    theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(Icons.schedule_rounded,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Text('${story.readingMinutes} min read',
                              style: theme.textTheme.bodySmall),
                        ]),
                        const SizedBox(height: 8),
                        const Divider(height: 40),
                        _StoryBody(body: story.body, fontScale: fontScale),
                        const SizedBox(height: 36),
                        _LifeLessonCard(lesson: story.lifeLesson),
                        const SizedBox(height: 36),
                        _RecommendedBooks(books: story.recommendedBooks),
                        const SizedBox(height: 44),
                        _ReflectInvitation(story: story),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StoryBody extends StatelessWidget {
  const _StoryBody({required this.body, required this.fontScale});

  final String body;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = body.trim().split(RegExp(r'\n\s*\n'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          if (block.startsWith('## '))
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 14),
              child: Text(
                block.substring(3).trim(),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontSize: 20 * fontScale),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                block.trim(),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontSize: 18 * fontScale, height: 1.75),
              ),
            ),
      ],
    );
  }
}

class _LifeLessonCard extends StatelessWidget {
  const _LifeLessonCard({required this.lesson});

  final String lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THE LESSON',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 10),
          Text(
            lesson,
            style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic, height: 1.6, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBooks extends StatelessWidget {
  const _RecommendedBooks({required this.books});

  final List<RecommendedBook> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('If this stayed with you, read next',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final b in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: b.title,
                          style: theme.textTheme.titleMedium),
                      TextSpan(
                          text: '  —  ${b.author}',
                          style: theme.textTheme.bodySmall),
                    ]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The signature moment of the app: the story ends,
/// and the page turns toward the reader.
class _ReflectInvitation extends StatelessWidget {
  const _ReflectInvitation({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 36),
        Text(
          'What did you learn today?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'A story only becomes yours when you write down what it changed.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              context.push(Routes.reflectionPath(story.id)),
          child: const Text('Reflect'),
        ),
      ],
    );
  }
}

// ═══════════ features/reflection/reflection_screen.dart ═══════════

/// A quiet journal page. Three questions, plenty of room, one button.
class ReflectionScreen extends ConsumerStatefulWidget {
  const ReflectionScreen({super.key, required this.storyId});

  final String storyId;

  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  final _touched = TextEditingController();
  final _lesson = TextEditingController();
  final _action = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _touched.dispose();
    _lesson.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _save(String storyTitle) async {
    if (_touched.text.trim().isEmpty &&
        _lesson.text.trim().isEmpty &&
        _action.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Write at least one thought before saving.')));
      return;
    }
    setState(() => _saving = true);
    await ref.read(reflectionsProvider.notifier).save(Reflection(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          storyId: widget.storyId,
          storyTitle: storyTitle,
          createdAt: DateTime.now(),
          touchedMost: _touched.text.trim(),
          lessonToApply: _lesson.text.trim(),
          actionToday: _action.text.trim(),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reflection saved to your journal.')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storyAsync = ref.watch(storyByIdProvider(widget.storyId));
    final storyTitle = storyAsync.valueOrNull?.title ?? '';
    final dateLabel = MaterialLocalizations.of(context)
        .formatFullDate(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Reflection')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text(dateLabel, style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                if (storyTitle.isNotEmpty)
                  Text('After reading “$storyTitle”',
                      style: theme.textTheme.headlineSmall),
                const SizedBox(height: 28),
                _JournalPrompt(
                  question: 'What touched you most?',
                  hint: 'A sentence, a moment, a person…',
                  controller: _touched,
                ),
                _JournalPrompt(
                  question: 'What lesson will you apply?',
                  hint: 'In your own words…',
                  controller: _lesson,
                ),
                _JournalPrompt(
                  question: 'What action will you take today?',
                  hint: 'Small is fine. Small is best.',
                  controller: _action,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : () => _save(storyTitle),
                  child: Text(_saving ? 'Saving…' : 'Save reflection'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your reflections stay on this device. No account, no cloud, no audience.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalPrompt extends StatelessWidget {
  const _JournalPrompt({
    required this.question,
    required this.hint,
    required this.controller,
  });

  final String question;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}

// ═══════════ features/profile/profile_screen.dart ═══════════

/// Your growth, not your engagement.
/// Stats here count what matters: stories finished, reflections written,
/// days of showing up.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(userStatsProvider);
    final storiesAsync = ref.watch(storiesProvider);
    final reading = ref.watch(readingStateProvider);
    final reflectionsAsync = ref.watch(reflectionsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your journey')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ---- Growth stats ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: statsAsync.when(
              loading: () => const SizedBox(height: 96),
              error: (_, __) => const SizedBox.shrink(),
              data: (stats) => Row(
                children: [
                  _StatCard(
                      value: '${stats.storiesRead}', label: 'Stories\nread'),
                  const SizedBox(width: 12),
                  _StatCard(
                      value: '${stats.reflectionCount}',
                      label: 'Reflections\nwritten'),
                  const SizedBox(width: 12),
                  _StatCard(
                      value: '${stats.readingStreak}',
                      label: 'Day\nstreak',
                      accent: stats.readingStreak > 0),
                ],
              ),
            ),
          ),

          // ---- Bookmarks ----
          const SectionHeading('Bookmarks'),
          storiesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (stories) {
              final bookmarked = stories
                  .where((s) => reading.bookmarks.contains(s.id))
                  .toList();
              if (bookmarked.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Stories you bookmark will wait for you here.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: [
                  for (final story in bookmarked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: StoryRowCard(
                        story: story,
                        onTap: () {
                          ref
                              .read(readingStateProvider.notifier)
                              .openedStory(story.id);
                          context.push(Routes.readerPath(story.id));
                        },
                        trailing: Icon(Icons.bookmark_rounded,
                            size: 20, color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              );
            },
          ),

          // ---- Journal ----
          const SectionHeading('Your journal'),
          reflectionsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (reflections) {
              if (reflections.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Finish a story and write a reflection — your first journal entry begins there.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in reflections.take(5))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(r.createdAt),
                                style: theme.textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text('On “${r.storyTitle}”',
                                  style: theme.textTheme.titleMedium),
                              if (r.lessonToApply.isNotEmpty ||
                                  r.touchedMost.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  r.lessonToApply.isNotEmpty
                                      ? r.lessonToApply
                                      : r.touchedMost,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontStyle: FontStyle.italic),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // ---- Settings ----
          const SectionHeading('Settings'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dark_mode_outlined, size: 22),
                    title: Text('Appearance',
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(_themeLabel(themeMode),
                        style: theme.textTheme.bodySmall),
                    trailing: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.bodySmall,
                      ),
                      segments: const [
                        ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined, size: 16)),
                        ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.smartphone, size: 16)),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined, size: 16)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) =>
                          ref.read(themeModeProvider.notifier).set(s.first),
                    ),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.lock_outline, size: 22),
                    title: Text('Privacy',
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(
                        'Everything is stored on this device. No account needed.',
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Read  •  Reflect  •  Rebuild',
              style:
                  theme.textTheme.labelMedium?.copyWith(letterSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Follows system',
      };
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: accent
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.headlineMedium?.copyWith(
                    color: accent ? theme.colorScheme.primary : null)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.25)),
          ],
        ),
      ),
    );
  }
}

// ═══════════ app.dart ═══════════

class ThinkUpliftApp extends ConsumerWidget {
  const ThinkUpliftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(
        isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);

    return MaterialApp.router(
      title: "ThinkUplift",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}

// ═══════════ main.dart ═══════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase-ready: when the backend arrives, initialize it here —
  //   await Firebase.initializeApp(...);
  // and swap the repository providers in app_providers.dart.
  final store = await LocalStore.init();

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const ThinkUpliftApp(),
    ),
  );
}
