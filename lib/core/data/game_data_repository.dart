import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_models.dart';

final gameDataProvider = Provider<GameDataRepository>(
  (Ref ref) => throw StateError('GameDataRepository was not initialized'),
);

class GameDataRepository {
  GameDataRepository({
    required this.trivia,
    required this.truthOrDare,
    required this.pictionary,
    required this.acting,
    required this.countdown,
    required this.imposterWords,
  });
  final List<TriviaQuestion> trivia;
  final List<TruthDareCard> truthOrDare;
  final List<PictionaryPrompt> pictionary;
  final List<ActingPrompt> acting;
  final List<CountdownPrompt> countdown;
  final List<ImposterWord> imposterWords;

  static Future<GameDataRepository> load() async {
    Future<List<Map<String, dynamic>>> loadList(String name) async {
      final source = await rootBundle.loadString('assets/data/$name.json');
      return (jsonDecode(source) as List<dynamic>).cast<Map<String, dynamic>>();
    }

    final values = await Future.wait<List<Map<String, dynamic>>>(
      <Future<List<Map<String, dynamic>>>>[
        loadList('trivia'),
        loadList('truth_or_dare'),
        loadList('pictionary'),
        loadList('act_it_out'),
        loadList('countdown'),
        loadList('imposter_words'),
      ],
    );
    return GameDataRepository(
      trivia: values[0].map(TriviaQuestion.fromJson).toList(growable: false),
      truthOrDare: values[1]
          .map(TruthDareCard.fromJson)
          .toList(growable: false),
      pictionary: values[2]
          .map(PictionaryPrompt.fromJson)
          .toList(growable: false),
      acting: values[3].map(ActingPrompt.fromJson).toList(growable: false),
      countdown: values[4]
          .map(CountdownPrompt.fromJson)
          .toList(growable: false),
      imposterWords: values[5]
          .map(ImposterWord.fromJson)
          .toList(growable: false),
    )..validate();
  }

  void validate() {
    final errors = <String>[];
    void validateIds(String name, Iterable<String> ids, int expected) {
      if (ids.length != expected) {
        errors.add('$name expected $expected, found ${ids.length}');
      }
      if (ids.toSet().length != ids.length) {
        errors.add('$name has duplicate IDs');
      }
      if (ids.any((String id) => id.trim().isEmpty)) {
        errors.add('$name has blank IDs');
      }
    }

    validateIds('trivia', trivia.map((TriviaQuestion item) => item.id), 1300);
    validateIds(
      'truth/dare',
      truthOrDare.map((TruthDareCard item) => item.id),
      200,
    );
    validateIds(
      'pictionary',
      pictionary.map((PictionaryPrompt item) => item.id),
      194,
    );
    validateIds('acting', acting.map((ActingPrompt item) => item.id), 420);
    validateIds(
      'countdown',
      countdown.map((CountdownPrompt item) => item.id),
      316,
    );
    validateIds(
      'imposter words',
      imposterWords.map((ImposterWord item) => item.id),
      231,
    );
    void uniqueText(String name, Iterable<String> values) {
      final normalized = values
          .map((String value) => value.trim().toLowerCase())
          .toList();
      if (normalized.any((String value) => value.isEmpty)) {
        errors.add('$name contains blank text');
      }
      if (normalized.toSet().length != normalized.length) {
        errors.add('$name contains duplicate text');
      }
    }

    bool outside<T>(Iterable<T> values, Set<T> allowed) =>
        values.any((T value) => !allowed.contains(value));

    uniqueText('trivia', trivia.map((TriviaQuestion item) => item.question));
    uniqueText(
      'truth/dare',
      truthOrDare.map((TruthDareCard item) => item.text),
    );
    uniqueText(
      'pictionary',
      pictionary.map((PictionaryPrompt item) => item.word),
    );
    uniqueText('acting', acting.map((ActingPrompt item) => item.text));
    uniqueText('countdown', countdown.map((CountdownPrompt item) => item.text));
    uniqueText(
      'imposter words',
      imposterWords.map((ImposterWord item) => item.word),
    );
    final imposterGroups = <String, List<ImposterWord>>{};
    for (final word in imposterWords) {
      if (word.groupId.trim().isEmpty || word.hint.trim().isEmpty) {
        errors.add('Imposter word ${word.id} has blank group metadata');
        continue;
      }
      imposterGroups
          .putIfAbsent(word.groupId, () => <ImposterWord>[])
          .add(word);
    }
    for (final entry in imposterGroups.entries) {
      final group = entry.value;
      if (group.length < 2) {
        errors.add('Imposter group ${entry.key} needs at least two words');
      }
      if (group.map((ImposterWord word) => word.category).toSet().length != 1) {
        errors.add('Imposter group ${entry.key} crosses categories');
      }
      if (group
              .map((ImposterWord word) => word.hint.toLowerCase())
              .toSet()
              .length !=
          1) {
        errors.add('Imposter group ${entry.key} has inconsistent hints');
      }
      final hint = group.first.hint.trim().toLowerCase();
      if (group.any((ImposterWord word) {
        final answer = word.word.trim().toLowerCase();
        return hint == answer || hint.contains(answer) || answer.contains(hint);
      })) {
        errors.add('Imposter group ${entry.key} has a revealing hint');
      }
    }
    if (outside(trivia.map((TriviaQuestion item) => item.difficulty), <String>{
      'easy',
      'medium',
      'hard',
    })) {
      errors.add('Trivia contains an invalid difficulty');
    }
    if (outside(
      pictionary.map((PictionaryPrompt item) => item.difficulty),
      <String>{'easy', 'medium', 'hard'},
    )) {
      errors.add('Pictionary contains an invalid difficulty');
    }
    if (outside(truthOrDare.map((TruthDareCard item) => item.type), <String>{
          'truth',
          'dare',
        }) ||
        outside(
          truthOrDare.map((TruthDareCard item) => item.category),
          <String>{'Chill', 'Funny', 'Friends', 'Bold'},
        ) ||
        outside(truthOrDare.map((TruthDareCard item) => item.intensity), <int>{
          1,
          2,
          3,
        })) {
      errors.add(
        'Truth or Dare contains an invalid type, category, or intensity',
      );
    }
    if (outside(countdown.map((CountdownPrompt item) => item.level), <int>{
      1,
      2,
      3,
      4,
      5,
    })) {
      errors.add('Countdown contains an invalid level');
    }
    if (trivia.any(
      (TriviaQuestion item) =>
          item.question.trim().isEmpty || item.answer.trim().isEmpty,
    )) {
      errors.add('Trivia contains a blank question or answer');
    }
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
  }

  T pick<T>(
    List<T> source,
    Random random, {
    Set<String> excludedIds = const <String>{},
    String Function(T)? idOf,
  }) {
    final available = idOf == null
        ? source
        : source.where((T item) => !excludedIds.contains(idOf(item))).toList();
    final pool = available.isEmpty ? source : available;
    return pool[random.nextInt(pool.length)];
  }
}
