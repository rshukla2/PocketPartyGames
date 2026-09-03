import 'dart:async';
import 'dart:math';

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

enum _Phase { setup, reveal, discuss, result }

class ImposterScreen extends ConsumerStatefulWidget {
  const ImposterScreen({super.key});
  @override
  ConsumerState<ImposterScreen> createState() => _ImposterScreenState();
}

class _ImposterScreenState extends ConsumerState<ImposterScreen> {
  _Phase phase = _Phase.setup;
  List<Player> selected = <Player>[];
  String category = 'Random';
  int imposterCount = 1;
  int minutes = 3;
  int revealIndex = 0;
  bool showing = false;
  late ImposterWord secret;
  Set<String> imposters = <String>{};
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
    if (selected.isEmpty) selected = List<Player>.from(app.players.take(6));
    return PopScope(
      canPop: phase == _Phase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Imposter',
        style: PartyGameStyle.imposter,
        tone: switch (phase) {
          _Phase.reveal => PartyScreenTone.secret,
          _Phase.result => PartyScreenTone.danger,
          _ => PartyScreenTone.standard,
        },
        subtitle: switch (phase) {
          _Phase.setup => 'Pass & Play word bluffing',
          _Phase.reveal => 'Private role ${revealIndex + 1}/${selected.length}',
          _Phase.discuss => 'Give clues and find the bluff',
          _Phase.result => 'Role reveal',
        },
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) => switch (phase) {
    _Phase.setup => _setup(app),
    _Phase.reveal => _reveal(),
    _Phase.discuss => _discuss(),
    _Phase.result => _result(),
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
        Text('Players', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        PlayerChips(
          players: app.players,
          minimum: 3,
          onChanged: (List<Player> value) => setState(() => selected = value),
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
        Text('Imposters: $imposterCount'),
        PartySlider(
          value: imposterCount.toDouble(),
          min: maxImposters == 1 ? 0 : 1,
          max: maxImposters.toDouble(),
          divisions: maxImposters - 1 == 0 ? null : maxImposters - 1,
          label: '$imposterCount',
          onChanged: maxImposters == 1
              ? null
              : (double value) => setState(() => imposterCount = value.round()),
        ),
        Text('Discussion: ${minutes == 0 ? 'No timer' : '$minutes minutes'}'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<int>>[
            ButtonSegment(value: 0, label: Text('Off')),
            ButtonSegment(value: 1, label: Text('1m')),
            ButtonSegment(value: 3, label: Text('3m')),
            ButtonSegment(value: 5, label: Text('5m')),
          ],
          selected: <int>{minutes},
          onSelectionChanged: (Set<int> value) =>
              setState(() => minutes = value.first),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: selected.length < 3 ? null : _start,
          icon: const Icon(Icons.visibility_off),
          label: const Text('DEAL SECRET ROLES'),
        ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/nearby', extra: 'imposter'),
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('USE NEARBY PHONES'),
          ),
        ],
      ],
    );
  }

  Widget _reveal() {
    final player = selected[revealIndex];
    final isImposter = imposters.contains(player.id);
    return Padding(
      key: ValueKey<String>('reveal-$revealIndex-$showing'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerAvatar(player: player, radius: 42),
          const SizedBox(height: 16),
          Text(
            showing
                ? 'YOUR SECRET ROLE'
                : 'PASS TO ${player.name.toUpperCase()}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          GradientCard(
            colors: showing
                ? isImposter
                      ? const <Color>[PartyColors.coral, PartyColors.nearBlack]
                      : const <Color>[PartyColors.blue, PartyColors.purple]
                : const <Color>[PartyColors.nearBlack, PartyColors.purple],
            child: SizedBox(
              height: 190,
              child: Center(
                child: showing
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            isImposter
                                ? '🕵️ IMPOSTER'
                                : secret.word.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isImposter
                                ? 'Bluff your way through the clues.'
                                : 'Give a clue without saying the word.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : const Text(
                        'Hold the phone privately, then tap below.',
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              if (!showing) {
                setState(() => showing = true);
              } else if (revealIndex + 1 < selected.length) {
                setState(() {
                  revealIndex++;
                  showing = false;
                });
              } else {
                _beginDiscussion();
              }
            },
            icon: Icon(showing ? Icons.check : Icons.visibility),
            label: Text(
              showing
                  ? (revealIndex + 1 == selected.length
                        ? 'START DISCUSSION'
                        : 'HIDE & PASS')
                  : 'SHOW MY ROLE',
            ),
          ),
        ],
      ),
    );
  }

  Widget _discuss() => Padding(
    key: ValueKey<int>(seconds),
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const StickerBadge(emoji: '💬', size: 104),
        const SizedBox(height: 22),
        Text(
          'DISCUSS & ACCUSE',
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Go around giving clues. Listen for someone who is vague, copying, or bluffing.',
          textAlign: TextAlign.center,
        ),
        if (minutes > 0) ...<Widget>[
          const SizedBox(height: 28),
          ResponsivePartyText(
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
            minFontSize: 52,
            maxFontSize: 84,
            maxLines: 1,
          ),
          LinearProgressIndicator(value: seconds / (minutes * 60)),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _showResult,
          icon: const Icon(Icons.how_to_vote),
          label: const Text('REVEAL IMPOSTERS'),
        ),
      ],
    ),
  );

  Widget _result() {
    final revealed = selected
        .where((Player player) => imposters.contains(player.id))
        .toList();
    return ListView(
      key: const ValueKey<String>('imposter-result'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🎭', size: 104)),
        const SizedBox(height: 22),
        Text(
          'THE WORD WAS',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ResponsivePartyText(
          secret.word.toUpperCase(),
          minFontSize: 42,
          maxFontSize: 76,
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        ...revealed.map(
          (Player player) => PartyCard(
            child: ListTile(
              leading: PlayerAvatar(player: player),
              title: Text(player.name),
              subtitle: const Text('IMPOSTER'),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _start,
          child: const Text('NEW WORD · SAME PLAYERS'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => phase = _Phase.setup),
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
    final pool = category == 'Random'
        ? data.imposterWords
        : data.imposterWords
              .where((ImposterWord item) => item.category == category)
              .toList();
    final random = ref.read(randomProvider);
    final shuffled = List<Player>.from(selected)..shuffle(random);
    setState(() {
      secret = pool[random.nextInt(pool.length)];
      imposters = shuffled
          .take(imposterCount)
          .map((Player player) => player.id)
          .toSet();
      revealIndex = 0;
      showing = false;
      phase = _Phase.reveal;
    });
  }

  void _beginDiscussion() {
    timer?.cancel();
    setState(() {
      seconds = minutes * 60;
      phase = _Phase.discuss;
    });
    if (minutes > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
        if (!mounted) return;
        if (seconds <= 1) {
          value.cancel();
          setState(() => seconds = 0);
        } else {
          setState(() => seconds--);
        }
      });
    }
  }

  void _showResult() {
    timer?.cancel();
    setState(() => phase = _Phase.result);
  }
}
