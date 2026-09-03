import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import 'trivia_engine.dart';

enum _TriviaPhase { menu, setup, handoff, playing, playerSummary, results }

class TriviaScreen extends ConsumerStatefulWidget {
  const TriviaScreen({super.key});

  @override
  ConsumerState<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends ConsumerState<TriviaScreen> {
  _TriviaPhase phase = _TriviaPhase.menu;
  bool versus = false;
  String category = 'all';
  TriviaDifficultyFilter difficulty = TriviaDifficultyFilter.mixed;
  TriviaTurnOrder turnOrder = TriviaTurnOrder.fullSetEach;
  int questionCount = 10;
  int timerSeconds = 30;
  List<Player> selected = <Player>[];
  List<TriviaTurn> turns = <TriviaTurn>[];
  final scores = <String, int>{};
  final correctByPlayer = <String, int>{};
  final answers = <bool>[];
  int index = 0;
  bool revealed = false;
  String? completedPlayerId;
  bool _selectionInitialized = false;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (!_selectionInitialized) {
      selected = List<Player>.from(app.players);
      _selectionInitialized = true;
    }
    return PopScope(
      canPop: phase == _TriviaPhase.menu || phase == _TriviaPhase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (await confirmLeaveGame(context) && context.mounted) context.pop();
      },
      child: PartyPage(
        title: 'Trivia',
        centerTitle: true,
        style: PartyGameStyle.trivia,
        tone: switch (phase) {
          _TriviaPhase.handoff => PartyScreenTone.secret,
          _TriviaPhase.playing => PartyScreenTone.action,
          _TriviaPhase.playerSummary ||
          _TriviaPhase.results => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: _subtitle,
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  String? get _subtitle => switch (phase) {
    _TriviaPhase.menu => null,
    _TriviaPhase.setup => versus ? 'Pass & Play setup' : 'Solo Sprint setup',
    _TriviaPhase.handoff => 'Pass the phone',
    _TriviaPhase.playing =>
      versus
          ? '${_playerForTurn(turns[index]).name} · Question ${turns[index].questionNumber} of $questionCount'
          : 'Question ${index + 1} of ${turns.length}',
    _TriviaPhase.playerSummary => 'Set complete',
    _TriviaPhase.results => 'Challenge complete',
  };

  Widget _content(AppState app) => switch (phase) {
    _TriviaPhase.menu => _menu(app),
    _TriviaPhase.setup => _setup(app),
    _TriviaPhase.handoff => _handoff(),
    _TriviaPhase.playing => _play(),
    _TriviaPhase.playerSummary => _playerSummary(),
    _TriviaPhase.results => _results(),
  };

  Widget _menu(AppState app) => ListView(
    key: const ValueKey<String>('trivia-menu'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      GradientCard(
        colors: const <Color>[PartyColors.blue, PartyColors.purple],
        onTap: () => setState(() {
          versus = false;
          questionCount = questionCount.clamp(5, 25);
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
          selected = List<Player>.from(app.players);
          _clampQuestionCount(ref.read(gameDataProvider));
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
    final data = ref.watch(gameDataProvider);
    final availability = versus && selected.isNotEmpty
        ? TriviaDeckPlanner(questions: data.trivia).availability(
            category: category,
            difficulty: difficulty,
            playerCount: selected.length,
          )
        : null;
    final maximum = versus ? availability?.maxQuestionsPerPlayer ?? 0 : 25;
    final canStart =
        !versus ||
        (selected.length >= 2 && availability != null && availability.canPlay);
    final sliderMinimum = maximum <= 5 ? 4 : 5;
    final sliderMaximum = maximum <= 5 ? 5 : maximum;

    return ListView(
      key: const ValueKey<String>('trivia-setup'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PartyDropdownField<String>(
          label: 'Category',
          initialValue: category,
          items: categories
              .map(
                (String value) => DropdownMenuItem(
                  value: value,
                  child: Text(_categoryTitle(value)),
                ),
              )
              .toList(),
          onChanged: (String? value) => setState(() {
            category = value ?? 'all';
            _clampQuestionCount(data);
          }),
        ),
        const SizedBox(height: 18),
        Text(
          'DIFFICULTY',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
        const SizedBox(height: 7),
        SegmentedButton<TriviaDifficultyFilter>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          segments: const <ButtonSegment<TriviaDifficultyFilter>>[
            ButtonSegment(
              value: TriviaDifficultyFilter.mixed,
              label: _SegmentLabel('Mixed'),
            ),
            ButtonSegment(
              value: TriviaDifficultyFilter.easy,
              label: _SegmentLabel('Easy'),
            ),
            ButtonSegment(
              value: TriviaDifficultyFilter.medium,
              label: _SegmentLabel('Medium'),
            ),
            ButtonSegment(
              value: TriviaDifficultyFilter.hard,
              label: _SegmentLabel('Hard'),
            ),
          ],
          selected: <TriviaDifficultyFilter>{difficulty},
          onSelectionChanged: (values) => setState(() {
            difficulty = values.first;
            _clampQuestionCount(data);
          }),
        ),
        const SizedBox(height: 20),
        Text(
          '${versus ? 'QUESTIONS PER PLAYER' : 'QUESTIONS'}: $questionCount',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        PartySlider(
          value: questionCount.clamp(sliderMinimum, sliderMaximum).toDouble(),
          min: sliderMinimum.toDouble(),
          max: sliderMaximum.toDouble(),
          divisions: sliderMaximum - sliderMinimum,
          label: '$questionCount',
          onChanged: maximum <= 5
              ? null
              : (double value) => setState(() => questionCount = value.round()),
        ),
        if (versus) ..._capacityMessage(availability),
        const SizedBox(height: 12),
        Text(
          'TIMER: ${timerSeconds == 0 ? 'OFF' : '${timerSeconds}s'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 7),
        SegmentedButton<int>(
          showSelectedIcon: false,
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
          const SizedBox(height: 20),
          Text(
            'TURN STYLE',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          const SizedBox(height: 7),
          SegmentedButton<TriviaTurnOrder>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            segments: const <ButtonSegment<TriviaTurnOrder>>[
              ButtonSegment(
                value: TriviaTurnOrder.fullSetEach,
                label: _SegmentLabel('Full set each'),
              ),
              ButtonSegment(
                value: TriviaTurnOrder.oneQuestionEach,
                label: _SegmentLabel('One each'),
              ),
            ],
            selected: <TriviaTurnOrder>{turnOrder},
            onSelectionChanged: (values) =>
                setState(() => turnOrder = values.first),
          ),
          const SizedBox(height: 7),
          Text(
            turnOrder == TriviaTurnOrder.fullSetEach
                ? 'Finish your whole set, then pass the phone.'
                : 'Pass the phone after every question.',
          ),
          const SizedBox(height: 20),
          Text('PLAYERS', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          PlayerChips(
            key: ValueKey<int>(app.players.length),
            players: app.players,
            onChanged: (List<Player> value) => setState(() {
              selected = value;
              _clampQuestionCount(data);
            }),
          ),
          if (selected.length < 2) ...<Widget>[
            const SizedBox(height: 10),
            const _CapacityCallout(
              message: 'Select at least 2 players to start Pass & Play.',
              danger: true,
            ),
          ],
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: canStart ? _start : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('START TRIVIA'),
        ),
      ],
    );
  }

  List<Widget> _capacityMessage(TriviaAvailability? availability) {
    if (selected.length < 2 || availability == null) return const <Widget>[];
    final maximum = availability.maxQuestionsPerPlayer;
    if (!availability.canPlay) {
      return <Widget>[
        const SizedBox(height: 8),
        _CapacityCallout(
          message:
              'Not enough unique ${difficulty == TriviaDifficultyFilter.mixed ? 'Mixed' : _title(difficulty.name)} questions for ${selected.length} players in ${_categoryTitle(category)}. Choose Mixed, All Categories, or fewer players.',
          danger: true,
        ),
      ];
    }
    if (maximum < 25) {
      return <Widget>[
        const SizedBox(height: 8),
        _CapacityCallout(
          message:
              'Up to $maximum unique questions per player with this setup. Every player gets the same difficulty opportunities.',
        ),
      ];
    }
    return const <Widget>[];
  }

  Widget _handoff() {
    final player = _playerForTurn(turns[index]);
    return Center(
      key: ValueKey<String>('trivia-handoff-${player.id}'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PlayerAvatar(player: player, radius: 42),
            const SizedBox(height: 24),
            Text(
              'PASS TO ${player.name.toUpperCase()}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            Text(
              '$questionCount questions are ready. Keep the screen private until ${player.name} has the phone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => setState(() => phase = _TriviaPhase.playing),
              icon: const Icon(Icons.visibility_rounded),
              label: Text('${player.name.toUpperCase()} IS READY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _play() {
    final turn = turns[index];
    final question = turn.question;
    final active = versus ? _playerForTurn(turn) : null;
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
              subtitle: Text(
                'Question ${turn.questionNumber} of $questionCount',
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

  Widget _playerSummary() {
    final player = selected.firstWhere(
      (candidate) => candidate.id == completedPlayerId,
    );
    final isLast = index == turns.length - 1;
    return Center(
      key: ValueKey<String>('trivia-summary-${player.id}'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const StickerBadge(emoji: '⭐', size: 96),
            const SizedBox(height: 22),
            Text(
              '${player.name.toUpperCase()}’S SET IS COMPLETE',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 14),
            Text(
              '${correctByPlayer[player.id] ?? 0} / $questionCount correct',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${scores[player.id] ?? 0} POINTS',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => setState(() {
                completedPlayerId = null;
                phase = isLast ? _TriviaPhase.results : _TriviaPhase.handoff;
              }),
              child: Text(isLast ? 'SEE FINAL RESULTS' : 'PASS THE PHONE'),
            ),
          ],
        ),
      ),
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
    final random = ref.read(randomProvider);
    final nextTurns = <TriviaTurn>[];
    if (versus) {
      final plan = TriviaDeckPlanner(questions: data.trivia).plan(
        category: category,
        difficulty: difficulty,
        playerIds: selected.map((player) => player.id).toList(),
        questionsPerPlayer: questionCount,
        turnOrder: turnOrder,
        random: random,
      );
      nextTurns.addAll(plan.turns);
    } else {
      final pool = data.trivia.where((question) {
        return (category == 'all' || question.category == category) &&
            (difficulty == TriviaDifficultyFilter.mixed ||
                question.difficulty == difficulty.dataValue);
      }).toList()..shuffle(random);
      nextTurns.addAll(<TriviaTurn>[
        for (final (questionIndex, question)
            in pool.take(questionCount).indexed)
          TriviaTurn(
            playerId: '',
            question: question,
            questionNumber: questionIndex + 1,
            pointValue: TriviaDeckPlanner.pointsForDifficulty(
              question.difficulty,
            ),
          ),
      ]);
    }
    setState(() {
      turns = nextTurns;
      index = 0;
      revealed = false;
      completedPlayerId = null;
      answers.clear();
      scores
        ..clear()
        ..addEntries(
          selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
        );
      correctByPlayer
        ..clear()
        ..addEntries(
          selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
        );
      phase = versus && turnOrder == TriviaTurnOrder.fullSetEach
          ? _TriviaPhase.handoff
          : _TriviaPhase.playing;
    });
  }

  void _score(bool correct) {
    final turn = turns[index];
    if (versus && correct) {
      scores[turn.playerId] = (scores[turn.playerId] ?? 0) + turn.pointValue;
      correctByPlayer[turn.playerId] =
          (correctByPlayer[turn.playerId] ?? 0) + 1;
    }
    answers.add(correct);
    setState(() {
      revealed = false;
      final isLastTurn = index + 1 >= turns.length;
      final playerSetComplete =
          versus &&
          turnOrder == TriviaTurnOrder.fullSetEach &&
          (isLastTurn || turns[index + 1].playerId != turn.playerId);
      if (playerSetComplete) {
        completedPlayerId = turn.playerId;
        if (!isLastTurn) index++;
        phase = _TriviaPhase.playerSummary;
      } else if (isLastTurn) {
        phase = _TriviaPhase.results;
      } else {
        index++;
      }
    });
  }

  void _clampQuestionCount(GameDataRepository data) {
    if (!versus || selected.isEmpty) {
      questionCount = questionCount.clamp(5, 25);
      return;
    }
    final maximum = TriviaDeckPlanner(questions: data.trivia)
        .availability(
          category: category,
          difficulty: difficulty,
          playerCount: selected.length,
        )
        .maxQuestionsPerPlayer;
    questionCount = maximum < 5 ? 5 : questionCount.clamp(5, maximum);
  }

  Player _playerForTurn(TriviaTurn turn) =>
      selected.firstWhere((player) => player.id == turn.playerId);

  String _title(String value) => value
      .split('-')
      .map((String word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  String _categoryTitle(String value) =>
      value == 'all' ? 'All Categories' : _title(value);
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}

class _CapacityCallout extends StatelessWidget {
  const _CapacityCallout({required this.message, this.danger = false});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger ? PartyColors.coral : PartyColors.yellow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PartyColors.nearBlack, width: 3),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: PartyColors.nearBlack,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
