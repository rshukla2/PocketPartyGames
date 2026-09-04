import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import 'imposter_engine.dart';

class ImposterScreen extends ConsumerStatefulWidget {
  const ImposterScreen({super.key});

  @override
  ConsumerState<ImposterScreen> createState() => _ImposterScreenState();
}

class _ImposterScreenState extends ConsumerState<ImposterScreen> {
  static const _engine = ImposterGameEngine();

  List<Player> selected = <Player>[];
  String category = 'Random';
  int imposterCount = 1;
  int discussionSeconds = 180;
  ImposterMode mode = ImposterMode.classic;
  bool hintsEnabled = false;
  bool multipleRounds = false;
  bool selectionInitialized = false;
  ImposterMatch? match;
  int revealIndex = 0;
  bool showing = false;
  Timer? timer;
  int seconds = 0;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (!selectionInitialized) {
      selected = List<Player>.from(app.players.take(6));
      selectionInitialized = true;
    }
    final current = match;
    final phase = current?.phase;
    return PopScope(
      canPop: current == null,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Imposter',
        style: PartyGameStyle.imposter,
        tone: switch (phase) {
          ImposterPhase.privateReveal => PartyScreenTone.secret,
          ImposterPhase.result when current?.outcome == ImposterOutcome.crew =>
            PartyScreenTone.success,
          ImposterPhase.result => PartyScreenTone.danger,
          _ => PartyScreenTone.standard,
        },
        subtitle: switch (phase) {
          null => 'Pass & Play word bluffing',
          ImposterPhase.privateReveal =>
            'Private word ${revealIndex + 1}/${selected.length}',
          ImposterPhase.discussion => 'Give clues and find the bluff',
          ImposterPhase.voting => 'Choose the player your group voted out',
          ImposterPhase.result => 'Final reveal',
        },
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) => switch (match?.phase) {
    null => _setup(app),
    ImposterPhase.privateReveal => _reveal(),
    ImposterPhase.discussion => _discussion(),
    ImposterPhase.voting => _voting(),
    ImposterPhase.result => _result(),
  };

  Widget _setup(AppState app) {
    final categories = <String>[
      'Random',
      ...ref
          .read(gameDataProvider)
          .imposterWords
          .map((ImposterWord item) => item.category)
          .toSet(),
    ];
    final maxImposters = max(1, (selected.length - 1) ~/ 2);
    if (imposterCount > maxImposters) imposterCount = maxImposters;
    return ListView(
      key: const ValueKey<String>('imposter-setup'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('PLAYERS', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        PlayerChips(
          players: app.players,
          minimum: 3,
          onChanged: (List<Player> value) => setState(() {
            selected = value;
            if (selected.length < 4) multipleRounds = false;
            imposterCount = min(
              imposterCount,
              max(1, (selected.length - 1) ~/ 2),
            );
          }),
        ),
        const SizedBox(height: 18),
        Text('ROLE MODE', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ImposterMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ImposterMode>>[
            ButtonSegment(value: ImposterMode.classic, label: Text('CLASSIC')),
            ButtonSegment(value: ImposterMode.oddWord, label: Text('ODD WORD')),
          ],
          selected: <ImposterMode>{mode},
          onSelectionChanged: (Set<ImposterMode> value) => setState(() {
            mode = value.first;
            if (mode == ImposterMode.oddWord) hintsEnabled = false;
          }),
        ),
        const SizedBox(height: 8),
        Text(
          mode == ImposterMode.classic
              ? 'The Crew shares a word. Imposters know their role and bluff.'
              : 'Everyone sees a word. Imposters get related odd words and do not know their role.',
        ),
        const SizedBox(height: 18),
        PartyDropdownField<String>(
          label: 'Secret word category',
          initialValue: category,
          items: categories
              .map(
                (String value) =>
                    DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (String? value) =>
              setState(() => category = value ?? 'Random'),
        ),
        const SizedBox(height: 16),
        Text('IMPOSTERS: $imposterCount'),
        PartySlider(
          value: imposterCount.toDouble(),
          min: maxImposters == 1 ? 0 : 1,
          max: maxImposters.toDouble(),
          divisions: maxImposters == 1 ? null : maxImposters - 1,
          label: '$imposterCount',
          onChanged: maxImposters == 1
              ? null
              : (double value) => setState(() => imposterCount = value.round()),
        ),
        if (mode == ImposterMode.classic)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: hintsEnabled,
            onChanged: (bool value) => setState(() => hintsEnabled = value),
            title: const Text('IMPOSTER HINT'),
            subtitle: const Text(
              'Give imposters a broad clue without revealing the Crew word.',
            ),
          ),
        if (selected.length >= 4)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: multipleRounds,
            onChanged: (bool value) => setState(() => multipleRounds = value),
            title: const Text('MULTIPLE ROUNDS'),
            subtitle: const Text(
              'Keep eliminating players until the Crew catches every imposter or the imposters reach parity.',
            ),
          ),
        Text(
          'DISCUSSION: ${discussionSeconds == 0 ? 'NO TIMER' : '${discussionSeconds ~/ 60} MIN'}',
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<int>>[
            ButtonSegment(value: 0, label: Text('OFF')),
            ButtonSegment(value: 60, label: Text('1M')),
            ButtonSegment(value: 180, label: Text('3M')),
            ButtonSegment(value: 300, label: Text('5M')),
          ],
          selected: <int>{discussionSeconds},
          onSelectionChanged: (Set<int> value) =>
              setState(() => discussionSeconds = value.first),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: selected.length < 3 ? null : _startLocal,
          icon: const Icon(Icons.visibility_off),
          label: Text(
            mode == ImposterMode.classic
                ? 'DEAL SECRET ROLES'
                : 'DEAL SECRET WORDS',
          ),
        ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: selected.length < 3 ? null : _startNearby,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('USE NEARBY PHONES'),
          ),
        ],
      ],
    );
  }

  Widget _reveal() {
    final current = match!;
    final player = selected[revealIndex];
    final assignment = current.assignments[player.id]!;
    final oddWord = current.setup.mode == ImposterMode.oddWord;
    return SingleChildScrollView(
      key: ValueKey<String>('reveal-$revealIndex-$showing'),
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: max(0, MediaQuery.sizeOf(context).height - 190),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PlayerNameBadge(player: player),
            const SizedBox(height: 16),
            Text(
              showing
                  ? (oddWord ? 'YOUR SECRET WORD' : 'YOUR SECRET ROLE')
                  : 'PASS TO ${player.name.toUpperCase()}',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            GradientCard(
              colors: showing && assignment.isImposter && !oddWord
                  ? const <Color>[PartyColors.coral, PartyColors.nearBlack]
                  : const <Color>[PartyColors.nearBlack, PartyColors.purple],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 190),
                child: Center(
                  child: showing
                      ? _assignmentReveal(assignment, oddWord)
                      : const Text(
                          'Hold the phone privately, then tap below.',
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _advanceReveal,
              icon: Icon(showing ? Icons.check : Icons.visibility),
              label: Text(
                showing
                    ? (revealIndex + 1 == selected.length
                          ? 'START DISCUSSION'
                          : 'HIDE & PASS')
                    : (oddWord ? 'SHOW MY WORD' : 'SHOW MY ROLE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assignmentReveal(ImposterAssignment assignment, bool oddWord) {
    if (!oddWord && assignment.isImposter) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '🕵️ IMPOSTER',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            assignment.hint == null
                ? 'Bluff your way through the clues.'
                : 'YOUR HINT: ${assignment.hint!.toUpperCase()}\nBluff without naming the hint.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ResponsivePartyText(
          assignment.word!.toUpperCase(),
          minFontSize: 34,
          maxFontSize: 58,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        const Text(
          'Give a clue without saying the word. Do not assume anyone else has the same word.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _discussion() {
    final current = match!;
    final round = current.rounds.last;
    return SingleChildScrollView(
      key: ValueKey<String>('discussion-${round.number}-$seconds'),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          if (round.banner != null) ...<Widget>[
            PartyCard(
              color: PartyColors.yellow,
              child: Text(
                round.banner!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 22),
          ],
          const StickerBadge(emoji: '💬', size: 104),
          const SizedBox(height: 22),
          Text(
            'DISCUSS & ACCUSE',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ROUND ${round.number} · ${current.activePlayerIds.length} PLAYERS LEFT',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Go around giving clues. Listen for someone who is vague, copying, or bluffing.',
            textAlign: TextAlign.center,
          ),
          if (current.setup.discussionSeconds > 0) ...<Widget>[
            const SizedBox(height: 28),
            ResponsivePartyText(
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              minFontSize: 52,
              maxFontSize: 84,
              maxLines: 1,
            ),
            LinearProgressIndicator(
              value: seconds / current.setup.discussionSeconds,
            ),
            if (seconds == 0) ...<Widget>[
              const SizedBox(height: 10),
              const PartyStatusPill(
                label: 'TIME IS UP · VOTE WHEN READY',
                color: PartyColors.yellow,
                icon: Icons.alarm,
              ),
            ],
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _beginVoting,
            icon: const Icon(Icons.how_to_vote),
            label: const Text('START VOTING'),
          ),
        ],
      ),
    );
  }

  Widget _voting() {
    final current = match!;
    final active = selected
        .where((Player player) => current.activePlayerIds.contains(player.id))
        .toList(growable: false);
    return ListView(
      key: ValueKey<String>('voting-${current.rounds.length}'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🗳️', size: 96)),
        const SizedBox(height: 24),
        Text(
          'WHO WAS VOTED OUT?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Finish your group vote, then tap the eliminated player. Your choice is final.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ...active.map(
          (Player player) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton(
              key: ValueKey<String>('vote-${player.id}'),
              onPressed: () => _eliminate(player.id),
              child: Text(player.name.toUpperCase()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final current = match!;
    final winner = current.outcome == ImposterOutcome.crew
        ? 'CREW WINS'
        : current.setup.imposterCount == 1
        ? 'IMPOSTER WINS'
        : 'IMPOSTERS WIN';
    final imposters = selected
        .where((Player player) => current.assignments[player.id]!.isImposter)
        .toList(growable: false);
    return ListView(
      key: const ValueKey<String>('imposter-result'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Center(
          child: StickerBadge(
            emoji: current.outcome == ImposterOutcome.crew ? '🏆' : '🎭',
            size: 104,
          ),
        ),
        const SizedBox(height: 22),
        ResponsivePartyText(
          winner,
          minFontSize: 42,
          maxFontSize: 72,
          maxLines: 2,
        ),
        const SizedBox(height: 18),
        Text(
          'THE CREW WORD WAS',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ResponsivePartyText(
          current.crewWord.toUpperCase(),
          minFontSize: 38,
          maxFontSize: 68,
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        ...imposters.map((Player player) {
          final assignment = current.assignments[player.id]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PartyCard(
              child: ListTile(
                title: Text(player.name),
                subtitle: Text(
                  current.setup.mode == ImposterMode.oddWord
                      ? 'IMPOSTER · ODD WORD: ${assignment.word}'
                      : 'IMPOSTER',
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _startLocal,
          child: Text(
            current.setup.mode == ImposterMode.oddWord
                ? 'NEW WORDS · SAME PLAYERS'
                : 'NEW WORD · SAME PLAYERS',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _returnToSetup,
          child: const Text('CHANGE SETUP'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  ImposterSetup _currentSetup() => ImposterSetup(
    players: List<Player>.unmodifiable(selected),
    category: category,
    imposterCount: imposterCount,
    discussionSeconds: discussionSeconds,
    mode: mode,
    hintsEnabled: hintsEnabled,
    multipleRounds: multipleRounds,
  );

  void _startLocal() {
    timer?.cancel();
    final created = _engine.createMatch(
      setup: _currentSetup(),
      words: ref.read(gameDataProvider).imposterWords,
      random: ref.read(randomProvider),
    );
    setState(() {
      match = created;
      revealIndex = 0;
      showing = false;
      seconds = 0;
    });
  }

  void _startNearby() {
    context.push('/nearby?game=imposter', extra: _currentSetup());
  }

  void _advanceReveal() {
    if (!showing) {
      setState(() => showing = true);
    } else if (revealIndex + 1 < selected.length) {
      setState(() {
        revealIndex++;
        showing = false;
      });
    } else {
      match = _engine.beginDiscussion(match!);
      _startDiscussionTimer();
    }
  }

  void _startDiscussionTimer() {
    timer?.cancel();
    setState(() => seconds = match!.setup.discussionSeconds);
    if (seconds == 0) return;
    timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
      if (!mounted) return;
      if (seconds <= 1) {
        value.cancel();
        setState(() => seconds = 0);
        _playTimerAlert();
      } else {
        setState(() => seconds--);
      }
    });
  }

  void _playTimerAlert() {
    final settings = ref.read(appControllerProvider).settings;
    if (settings.soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    if (settings.hapticsEnabled) {
      unawaited(HapticFeedback.heavyImpact());
    }
  }

  void _beginVoting() {
    timer?.cancel();
    setState(() => match = _engine.beginVoting(match!));
  }

  void _eliminate(String playerId) {
    final updated = _engine.eliminate(match!, playerId);
    setState(() => match = updated);
    if (updated.phase == ImposterPhase.discussion) {
      _startDiscussionTimer();
    }
  }

  void _returnToSetup() {
    timer?.cancel();
    setState(() {
      match = null;
      revealIndex = 0;
      showing = false;
      seconds = 0;
    });
  }
}
