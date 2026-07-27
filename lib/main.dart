// ============================================================
// ThinkUplift V1 — single-file build, v2
// (native share plugin removed; Share button now copies to clipboard)
// ============================================================
import 'dart:convert';

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
  factory Story.fromMap(Map<String, dynamic> map) => Story(
        id: map["id"] as String,
        title: map["title"] as String,
        subtitle: map["subtitle"] as String,
        category: map["category"] as String,
        readingMinutes: map["readingMinutes"] as int,
        body: map["body"] as String,
        lifeLesson: map["lifeLesson"] as String,
        reflectionQuestions:
            List<String>.from(map["reflectionQuestions"] as List),
        recommendedBooks: (map["recommendedBooks"] as List)
            .map((b) => RecommendedBook.fromMap(Map<String, dynamic>.from(b)))
            .toList(),
        coverColors: List<int>.from(map["coverColors"] as List),
        isTodaysStory: map["isTodaysStory"] as bool? ?? false,
        isFeatured: map["isFeatured"] as bool? ?? false,
      );

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

/// The five launch stories, bundled with the app.
/// Each follows the ThinkUplift writing structure:
/// hook → real human story → emotional turning point → lesson → action.
///
/// When the Firebase content pipeline arrives, this file is simply retired
/// and a FirebaseStoryRepository serves the same [Story] entity.
const demoStories = <Story>[
  Story(
    id: 'give-no-excuse-ever',
    title: 'Give No Excuse Ever',
    subtitle: 'The day I ran out of people to blame',
    category: 'Mindset',
    readingMinutes: 4,
    isTodaysStory: true,
    isFeatured: true,
    coverColors: [0xFF3D5A80, 0xFF98C1D9],
    body: '''
For three years, I kept a list of reasons my life wasn't working.

It was a good list. Honest, even. My father left when I was nine. My first boss took credit for my work. The city I grew up in had no opportunities. My college fund disappeared in a family dispute I was too young to understand.

Every item on that list was true. That was the problem.

## The list

I didn't write the list on paper. I carried it in my chest, and I recited it — to friends over tea, to my mother on Sunday calls, to strangers who asked why I hadn't finished my degree. People nodded. People sympathized. Sympathy feels almost like progress, if you don't look at it too closely.

Then one evening my cousin Ravi visited. Ravi drives a delivery van. He lost his right hand in a factory accident at twenty-two, learned to write with his left, and passed his accounting exams at thirty-one while working full shifts.

I recited my list. He listened all the way through, which nobody had done before. Then he asked one question:

"Okay. And what is your plan?"

I started the list again. He stopped me gently. "No — that is what happened to you. I asked what your plan is."

## The turning point

I had no plan. I had never had a plan. I had a defense.

That night I understood something that embarrassed me for weeks: I had been preparing for a trial that was never going to happen. There is no courtroom where you present your excuses and receive your lost years back. The list was accurate, and it was useless. Both things were true at once.

An excuse is a story about the past that asks nothing of you. A plan is a story about the future that asks everything.

## What changed

I did not become a different person overnight. I did one small thing: every time I caught myself reciting the list, I made myself finish the sentence with "...and here is what I will do about it this week."

Half the time, the second half of the sentence was tiny. Email one person. Read one chapter. Save one small amount. It didn't matter. The sentence had a new shape now, and the shape did the work.

Two years later I finished my degree at night school. The list still exists — everything on it still happened. I just stopped presenting it as evidence and started treating it as terrain.
''',
    lifeLesson:
        'Your excuses can be completely valid and completely useless at the same time. The question is never whether your reasons are real — it is what your plan is.',
    reflectionQuestions: [
      'What is one true excuse you have been carrying as a defense?',
      'If you finished it with "...and here is what I will do this week," what would the sentence say?',
    ],
    recommendedBooks: [
      RecommendedBook(title: 'Man\'s Search for Meaning', author: 'Viktor E. Frankl'),
      RecommendedBook(title: 'Extreme Ownership', author: 'Jocko Willink & Leif Babin'),
    ],
  ),
  Story(
    id: '143-days-in-jail',
    title: '143 Days in Jail',
    subtitle: 'What a locked door taught me about open ones',
    category: 'Rebuilding',
    readingMinutes: 5,
    isFeatured: true,
    coverColors: [0xFF33415C, 0xFF7D8CA3],
    body: '''
The worst part was not the door locking. It was hearing my own name read out loud in a room where nobody knew me, and realizing that to everyone present, the name and the charge were the same thing.

I was twenty-six. A business partner had forged documents; my signature sat next to his. It took 143 days for the truth to be sorted out. This is not a story about injustice, though. Plenty of men in that ward had done exactly what they were accused of, and one of them changed my life.

## The teacher

His name was Dawood. He was fifty-one and had been inside for six years. Every morning at five, before the noise started, he sat cross-legged on his mat with a book. Always a book. The prison library was two metal shelves, and he had read both of them, some titles four times.

For my first month, I did what most new men did: I replayed the past on a loop. The meeting where I should have read the papers. The friend I should not have trusted. I wore a groove in those memories like a path worn in grass.

Dawood watched me pace for a few weeks. Then one morning he held out a book — a worn biography of Abraham Lincoln — and said the sentence I have repeated to myself for eleven years since:

"Your body is in here for some months. Your mind does not have to serve the same sentence."

## The turning point

I read the Lincoln book in three days. Then a book on soil farming. Then a psychology textbook missing its cover. I was not reading for pleasure. I was reading the way a drowning man breathes.

Something strange happened around day sixty. The walls did not move, but they mattered less. I started keeping a notebook — lessons from each book, one page each. By day 143, the notebook had ninety-one pages.

The day I walked out, Dawood shook my hand and said, "Most men leave here angrier. Try to be the other kind."

## After

The case was dismissed. My old life was not waiting for me — the business was gone, some friends were gone. But the notebook came with me, and so did the habit. Five a.m. A book. A page of notes.

I rebuilt slowly: a small job, then a better one, then my own work again — this time reading every paper twice. The 143 days took things from me I will not get back. They also gave me the one habit that rebuilt everything else.

I did not choose the room. I chose what I did in it.
''',
    lifeLesson:
        'You cannot always choose your circumstances, but your mind never has to serve the same sentence as your situation. A daily habit of learning can survive any room.',
    reflectionQuestions: [
      'What "room" are you in right now that you did not choose?',
      'What is one habit that could keep your mind free inside it?',
    ],
    recommendedBooks: [
      RecommendedBook(title: 'The Obstacle Is the Way', author: 'Ryan Holiday'),
      RecommendedBook(title: 'Long Walk to Freedom', author: 'Nelson Mandela'),
    ],
  ),
  Story(
    id: 'the-brother-who-left-me',
    title: 'The Brother Who Left Me',
    subtitle: 'On loving people who choose to walk away',
    category: 'Family',
    readingMinutes: 4,
    coverColors: [0xFF6D597A, 0xFFB56576],
    body: '''
My brother Sameer stopped speaking to me on a Tuesday in March, and for four years I did not know why.

We had shared a room for sixteen years. He taught me to ride a bicycle by lying about how long he would hold the seat. When our father was in the hospital, we took turns sleeping in the corridor chair. I would have told you we were unbreakable, and I would have been sincere, and I would have been wrong.

## The silence

There was no dramatic fight. There was a property matter after our father passed — small, resolvable, the kind of thing families argue about at dinner and forget by dessert. Except we didn't. Words were said through relatives, which is the worst way words can travel, because relatives deliver the sentence but never the tone.

Then: silence. My calls went unanswered. My messages showed as read. At his daughter's wedding, I was not invited, and I learned about it from a photograph.

For two of those four years, I was consumed. I drafted long messages at midnight and deleted them at dawn. I argued with him constantly — in the shower, in traffic — winning debates he was not present for. The person occupying the most space in my head was a person who had removed me from his life entirely.

## The turning point

The shift came from my aunt, who is eighty-two and has buried two husbands and one child, and therefore does not waste words. I was recounting the whole history to her again when she interrupted:

"You keep knocking on a door and calling it love. Sometimes love is letting the door be a door."

She was not telling me to stop loving him. She was telling me to stop living at his doorstep.

## What I did

I wrote Sameer one final letter — not a case, not a defense, just three things: what he had meant to me, that my door would remain open without conditions, and that I would stop knocking on his. I mailed it, and then I did the hardest thing: I went back to my own life and actually lived it.

I will not pretend this story has the ending you might want. He has not called. Perhaps he never will.

But something unexpected returned to me: my mornings. My attention. The energy I had spent on an argument with a ghost went back into my children, my work, my own days. I still love my brother. I have simply stopped auditioning for a role in his life, and started fully playing the one in mine.

Some doors you keep open. You just stop standing in them.
''',
    lifeLesson:
        'You can love someone completely and still stop organizing your life around their absence. Leave the door open — then step away from it and live.',
    reflectionQuestions: [
      'Is there a relationship where you are "standing in the doorway" instead of living your life?',
      'What would it look like to leave the door open, but step away from it?',
    ],
    recommendedBooks: [
      RecommendedBook(title: 'The Four Agreements', author: 'Don Miguel Ruiz'),
      RecommendedBook(title: 'Necessary Losses', author: 'Judith Viorst'),
    ],
  ),
  Story(
    id: 'books-saved-my-life',
    title: 'Books Saved My Life',
    subtitle: 'A library card, a night shift, and a way out',
    category: 'Books',
    readingMinutes: 4,
    isFeatured: true,
    coverColors: [0xFF386641, 0xFFA7C957],
    body: '''
At nineteen, my entire world was a security guard's chair, a gate, and eleven hours of night.

I had failed my exams — not narrowly, completely. My family needed income, so I took the only job available: night watchman at a textile warehouse on the edge of town. My friends went to college. I went to a plastic chair under a tube light, six nights a week.

The first months, I did what the darkness invites you to do: I sat with my phone until it died around 2 a.m., and then I sat with my thoughts, which were worse.

## The box

The warehouse owner's father had passed away that year, and one night a truck delivered boxes of his belongings for storage. One box had split open. Books had spilled across the loading dock — I was told to repack them.

I picked up the first one to put it away and read the opening line standing up. I read the first chapter leaning against the shelf. I finished the book at 4 a.m. in my plastic chair, and for the first time in months, the night had gone somewhere.

The owner noticed the repacked box was often lighter by one book. Instead of firing me, he said, "Read them in order, at least. My father would have liked that."

## The turning point

There were over two hundred books in those boxes. History, biographies, old novels, a chemistry textbook, a book on public speaking with notes in the margins in a dead man's careful handwriting.

I made a rule: one book per week, one notebook page per book. Eleven hours of night is a curse if you are waiting for morning. It is a gift if you are reading. The same hours, the same chair — a different man sitting in it.

The chemistry textbook made me curious enough to retake my exams. The public speaking book made me bold enough to ask questions in class when I finally got there. Three years of nights gave me something my college classmates did not have: I had read two hundred books, and I knew exactly why I was there.

## Now

I teach at a small school today. On the first day of every year, I tell my students about the box on the loading dock, and I give each of them a library card application.

Not everyone gets a rescue. But almost everyone, at some point, gets a book. The difference is whether you pick it up.
''',
    lifeLesson:
        'The same empty hours can be a sentence or a scholarship. A book turns waiting time into building time — and almost everyone can reach one.',
    reflectionQuestions: [
      'Where in your week are "empty hours" you have been merely enduring?',
      'What is one book you could place inside those hours this week?',
    ],
    recommendedBooks: [
      RecommendedBook(title: 'Educated', author: 'Tara Westover'),
      RecommendedBook(title: 'The Autobiography of Malcolm X', author: 'Malcolm X & Alex Haley'),
    ],
  ),
  Story(
    id: 'rebuild-yourself',
    title: 'Rebuild Yourself',
    subtitle: 'What a demolished house taught me about starting over',
    category: 'Rebuilding',
    readingMinutes: 5,
    coverColors: [0xFF5F0F40, 0xFF9A8C98],
    body: '''
The year I turned forty, I lost my job, my marriage, and my father — in that order, in eleven months. People called it "a difficult year" in the same tone they would describe bad weather. From the inside, it did not feel like weather. It felt like demolition.

## The house

That winter, I moved back to my parents' town to settle my father's affairs. Next to his house stood a property everyone called the Sharma house — half-collapsed after a fire years earlier, black-streaked, roof open to the sky. It matched my mood so precisely that I avoided looking at it.

One morning I noticed an old man working alone in its rubble. Not clearing it — sorting it. Brick by brick, into piles: broken beyond use, damaged but usable, fully intact. He was there every morning. It took me two weeks to walk over and ask what he was doing.

"Rebuilding," he said, as if it were obvious.

"Why sort the old bricks? Why not just buy new ones?"

He straightened up and gave me a look I still think about. "Because most of the house is still good. People see a ruin and think everything must go. That is lazy looking. The fire took the roof and one wall. It did not take the foundation."

## The turning point

I went home and, feeling somewhat foolish, did what he was doing — on paper. Three columns. Everything in my life, sorted honestly:

Broken beyond use. Damaged but usable. Fully intact.

The first column was shorter than I expected. The marriage was there. The old job was there. The third column stunned me: my health. My skills — twenty years of them. Two friends who had called every single week of that terrible year. My mind, tired but working.

I had been describing myself as a ruin. The honest inventory said: a house with fire damage and a standing foundation. Those are different buildings. They require different plans.

## The rebuild

The old man took two years on the Sharma house. He worked in an order I later realized was deliberate: foundation first, then walls, then roof, then — only at the very end — paint.

I rebuilt in the same order. Foundation first: sleep, walking, meals at regular hours. Then walls: work, using the skills that had survived. The roof — new relationships, new place — came later. The paint, the parts of life that merely look good, came last of all.

He moved into that house. I visited him there before I left town. Same foundation, same good bricks, new roof.

"Everyone rebuilds someday," he told me at the door. "The only mistake is throwing away the good bricks."
''',
    lifeLesson:
        'After a collapse, take an honest inventory before you declare yourself a ruin. Most of your foundation usually survives. Rebuild in order: foundation, walls, roof — paint last.',
    reflectionQuestions: [
      'If you sorted your life into three piles today — broken, damaged but usable, intact — what would be in the "intact" pile?',
      'What is one "foundation" habit you could restore this week, before worrying about the paint?',
    ],
    recommendedBooks: [
      RecommendedBook(title: 'Option B', author: 'Sheryl Sandberg & Adam Grant'),
      RecommendedBook(title: 'Atomic Habits', author: 'James Clear'),
    ],
  ),
];

/// V1 category list. Kept alongside content so a remote repository
/// can later derive categories from data instead.
const demoCategories = <String>[
  'Rebuilding',
  'Mindset',
  'Books',
  'Purpose',
  'Family',
  'Learning',
];

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

  double getFontScale() => _prefs.getDouble(_kFontScale) ?? 1.0;
  Future<void> setFontScale(double scale) =>
      _prefs.setDouble(_kFontScale, scale);
}

// ═══════════ data/repositories/local_story_repository.dart ═══════════

/// V1 implementation: serves the bundled demo stories.
/// Replace with FirebaseStoryRepository later by changing one provider.
class LocalStoryRepository implements StoryRepository {
  @override
  Future<List<Story>> getAllStories() async => demoStories;

  @override
  Future<Story?> getStoryById(String id) async {
    for (final s in demoStories) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<String>> getCategories() async => demoCategories;
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
final storyRepositoryProvider =
    Provider<StoryRepository>((ref) => LocalStoryRepository());

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
