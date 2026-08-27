import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';

enum _TriviaPhase { menu, setup, playing, results }

class TriviaScreen extends ConsumerStatefulWidget {
  const TriviaScreen({super.key});
  @override
  ConsumerState<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends ConsumerState<TriviaScreen> {
  _TriviaPhase phase = _TriviaPhase.menu;
  bool versus = false;
  String category = 'all';
  String difficulty = 'all';
  int questionCount = 10;
  int timerSeconds = 30;
  List<Player> selected = <Player>[];
  List<TriviaQuestion> questions = <TriviaQuestion>[];
  final scores = <String, int>{};
  final answers = <bool>[];
  int index = 0;
  bool revealed = false;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (selected.isEmpty) selected = List<Player>.from(app.players.take(4));
    return PopScope(
      canPop: phase == _TriviaPhase.menu || phase == _TriviaPhase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (await confirmLeaveGame(context) && context.mounted) context.pop();
      },
      child: PartyPage(
        title: 'Trivia Vault',
        style: PartyGameStyle.trivia,
        tone: switch (phase) {
          _TriviaPhase.playing => PartyScreenTone.action,
          _TriviaPhase.results => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: _subtitle,
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  String get _subtitle => switch (phase) {
    _TriviaPhase.menu => '1,300 questions · 13 categories',
    _TriviaPhase.setup => versus ? 'Pass & Play setup' : 'Solo Sprint setup',
    _TriviaPhase.playing => 'Question ${index + 1} of ${questions.length}',
    _TriviaPhase.results => 'Challenge complete',
  };

  Widget _content(AppState app) => switch (phase) {
    _TriviaPhase.menu => _menu(),
    _TriviaPhase.setup => _setup(app),
    _TriviaPhase.playing => _play(),
    _TriviaPhase.results => _results(),
  };

  Widget _menu() => ListView(
    key: const ValueKey<String>('trivia-menu'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      GradientCard(
        colors: const <Color>[PartyColors.blue, PartyColors.purple],
        onTap: () => setState(() {
          versus = false;
          phase = _TriviaPhase.setup;
        }),
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Text('⚡', style: TextStyle(fontSize: 44)),
          title: Text(
            'SOLO SPRINT',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
          ),
          subtitle: Text('Test your knowledge and chase a high score.'),
          trailing: Icon(Icons.arrow_forward_rounded),
        ),
      ),
      const SizedBox(height: 14),
      GradientCard(
        colors: const <Color>[PartyColors.purple, PartyColors.pink],
        onTap: () => setState(() {
          versus = true;
          phase = _TriviaPhase.setup;
        }),
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Text('🏆', style: TextStyle(fontSize: 44)),
          title: Text(
            'PASS & PLAY',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
          ),
          subtitle: Text('Take turns, reveal answers, and score the group.'),
          trailing: Icon(Icons.arrow_forward_rounded),
        ),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => context.push('/trivia-browser'),
        icon: const Icon(Icons.menu_book_rounded),
        label: const Text('BROWSE QUESTION VAULT'),
      ),
      if (!kIsWeb) ...<Widget>[
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/nearby', extra: 'trivia-versus'),
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: const Text('PLAY ON NEARBY PHONES'),
        ),
      ],
    ],
  );

  Widget _setup(AppState app) {
    const categories = <String>[
      'all',
      'general',
      'science',
      'history',
      'geography',
      'movies-tv',
      'music',
      'sports',
      'pop-culture',
      'technology',
      'food-drink',
      'animals',
      'art-literature',
      'culture-mythology',
    ];
    return ListView(
      key: const ValueKey<String>('trivia-setup'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: categories
              .map(
                (String value) =>
                    DropdownMenuItem(value: value, child: Text(_title(value))),
              )
              .toList(),
          onChanged: (String? value) =>
              setState(() => category = value ?? 'all'),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment(value: 'all', label: Text('Mixed')),
            ButtonSegment(value: 'easy', label: Text('Easy')),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'hard', label: Text('Hard')),
          ],
          selected: <String>{difficulty},
          onSelectionChanged: (Set<String> values) =>
              setState(() => difficulty = values.first),
        ),
        const SizedBox(height: 16),
        Text(
          'Questions: $questionCount',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: questionCount.toDouble(),
          min: 5,
          max: versus ? 30 : 20,
          divisions: versus ? 5 : 3,
          label: '$questionCount',
          onChanged: (double value) =>
              setState(() => questionCount = (value / 5).round() * 5),
        ),
        Text('Timer: ${timerSeconds == 0 ? 'Off' : '${timerSeconds}s'}'),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment(value: 0, label: Text('Off')),
            ButtonSegment(value: 15, label: Text('15s')),
            ButtonSegment(value: 30, label: Text('30s')),
          ],
          selected: <int>{timerSeconds},
          onSelectionChanged: (Set<int> values) =>
              setState(() => timerSeconds = values.first),
        ),
        if (versus) ...<Widget>[
          const SizedBox(height: 18),
          Text('Players', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          PlayerChips(
            players: app.players,
            onChanged: (List<Player> value) => selected = value,
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('START TRIVIA'),
        ),
      ],
    );
  }

  Widget _play() {
    final question = questions[index];
    final active = versus ? selected[index % selected.length] : null;
    return ListView(
      key: ValueKey<String>('trivia-${question.id}-$revealed'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (active != null)
          PartyCard(
            child: ListTile(
              leading: PlayerAvatar(player: active),
              title: Text(
                '${active.name}’s turn',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Text('${scores[active.id] ?? 0} pts'),
            ),
          ),
        Chip(
          label: Text(
            '${_title(question.category)} · ${_title(question.difficulty)}',
          ),
        ),
        const SizedBox(height: 10),
        PartyCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ResponsivePartyText(
              question.question,
              minFontSize: 28,
              maxFontSize: 44,
              maxLines: 6,
              color: PartyColors.nearBlack,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!revealed)
          FilledButton.icon(
            onPressed: () => setState(() => revealed = true),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('REVEAL ANSWER'),
          )
        else ...<Widget>[
          GradientCard(
            colors: const <Color>[PartyColors.green, PartyColors.blue],
            child: Column(
              children: <Widget>[
                const Text(
                  'ANSWER',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PartyColors.nearBlack,
                  ),
                ),
                const SizedBox(height: 8),
                ResponsivePartyText(
                  question.answer,
                  minFontSize: 28,
                  maxFontSize: 46,
                  maxLines: 4,
                  color: PartyColors.nearBlack,
                ),
                if (question.explanation != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(question.explanation!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _score(false),
                  icon: const Icon(Icons.close),
                  label: const Text('MISSED'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _score(true),
                  icon: const Icon(Icons.check),
                  label: const Text('CORRECT'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _results() {
    final correct = answers.where((bool value) => value).length;
    return ListView(
      key: const ValueKey<String>('trivia-results'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🎉', size: 104)),
        const SizedBox(height: 22),
        Text(
          versus ? 'PARTY PODIUM' : '$correct / ${answers.length} CORRECT',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 16),
        if (versus) ScoreBoard(players: selected, scores: scores),
        const SizedBox(height: 20),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => phase = _TriviaPhase.setup),
          child: const Text('CHANGE SETUP'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  void _start() {
    final data = ref.read(gameDataProvider);
    var pool = data.trivia.where((TriviaQuestion item) {
      return (category == 'all' || item.category == category) &&
          (difficulty == 'all' || item.difficulty == difficulty);
    }).toList();
    if (pool.length < questionCount) {
      pool = data.trivia
          .where(
            (TriviaQuestion item) =>
                category == 'all' || item.category == category,
          )
          .toList();
    }
    pool.shuffle(ref.read(randomProvider));
    setState(() {
      questions = pool.take(questionCount).toList();
      index = 0;
      revealed = false;
      answers.clear();
      scores
        ..clear()
        ..addEntries(
          selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
        );
      phase = _TriviaPhase.playing;
    });
  }

  void _score(bool correct) {
    if (correct && versus) {
      final player = selected[index % selected.length];
      final difficultyPoints = questions[index].difficulty == 'hard'
          ? 3
          : questions[index].difficulty == 'medium'
          ? 2
          : 1;
      scores[player.id] = (scores[player.id] ?? 0) + difficultyPoints;
    }
    answers.add(correct);
    setState(() {
      if (index + 1 >= questions.length) {
        phase = _TriviaPhase.results;
      } else {
        index++;
        revealed = false;
      }
    });
  }

  String _title(String value) => value
      .split('-')
      .map((String word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
