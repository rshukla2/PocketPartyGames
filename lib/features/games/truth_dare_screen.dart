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
import 'truth_dare_engine.dart';

enum _Phase { setup, play, summary }

class TruthDareScreen extends ConsumerStatefulWidget {
  const TruthDareScreen({super.key});
  @override
  ConsumerState<TruthDareScreen> createState() => _TruthDareScreenState();
}

class _TruthDareScreenState extends ConsumerState<TruthDareScreen> {
  static const _engine = TruthDareGameEngine();
  _Phase phase = _Phase.setup;
  List<Player> selected = <Player>[];
  String category = 'Mixed';
  bool randomRotation = false;
  int playerIndex = 0;
  TruthDareCard? card;
  TruthDareSession? session;
  final used = <String>{};

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (selected.isEmpty) selected = List<Player>.from(app.players);
    return PopScope(
      canPop: phase == _Phase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Truth or Dare',
        centerTitle: true,
        style: PartyGameStyle.truthDare,
        tone: switch (phase) {
          _Phase.play when category == 'Bold' => PartyScreenTone.secret,
          _Phase.play when card?.type == 'dare' => PartyScreenTone.action,
          _Phase.summary => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: switch (phase) {
          _Phase.setup => null,
          _Phase.play => '${selected[playerIndex].name}’s turn',
          _Phase.summary => '${session?.history.length ?? 0} turns played',
        },
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) => switch (phase) {
    _Phase.setup => _setup(app),
    _Phase.play => _play(),
    _Phase.summary => _summary(),
  };

  Widget _setup(AppState app) => ListView(
    key: const ValueKey<String>('truth-setup'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('Players', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      PlayerChips(
        players: app.players,
        onChanged: (List<Player> value) => setState(() => selected = value),
      ),
      const SizedBox(height: 18),
      PartyDropdownField<String>(
        label: 'Card category',
        initialValue: category,
        items: const <String>['Mixed', 'Chill', 'Funny', 'Friends', 'Bold']
            .map(
              (String value) =>
                  DropdownMenuItem(value: value, child: Text(value)),
            )
            .toList(),
        onChanged: (String? value) =>
            setState(() => category = value ?? 'Mixed'),
      ),
      const SizedBox(height: 18),
      SwitchListTile(
        value: randomRotation,
        onChanged: (bool value) => setState(() => randomRotation = value),
        title: const Text('Random player rotation'),
        subtitle: const Text('Otherwise turns follow the roster order.'),
      ),
      if (category == 'Bold')
        const PartyCard(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Bold cards may involve social, physical, or privacy-related challenges. Anyone can decline or skip any card.',
            ),
          ),
        ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: selected.length < 2 ? null : _start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('START GAME'),
      ),
      if (selected.length < 2)
        const Text('Choose at least two players.', textAlign: TextAlign.center),
    ],
  );

  Widget _play() {
    final player = selected[playerIndex];
    final resources = session!.playerStates[player.id]!;
    return ListView(
      key: ValueKey<String>('truth-play-${card?.id}-$playerIndex'),
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Center(child: PlayerNameBadge(player: player)),
        const SizedBox(height: 10),
        Text(
          player.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        if (card == null) ...<Widget>[
          GradientCard(
            colors: const <Color>[PartyColors.pink, PartyColors.coral],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Choose a card. You can always skip anything that feels uncomfortable.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _draw('truth'),
            icon: const Icon(Icons.question_mark),
            label: const Text('TRUTH'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => _draw('dare'),
            icon: const Icon(Icons.bolt),
            label: const Text('DARE'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () =>
                _draw(ref.read(randomProvider).nextBool() ? 'truth' : 'dare'),
            icon: const Icon(Icons.casino),
            label: const Text('SURPRISE ME'),
          ),
        ] else ...<Widget>[
          GradientCard(
            colors: card!.type == 'truth'
                ? const <Color>[PartyColors.blue, PartyColors.purple]
                : const <Color>[PartyColors.pink, PartyColors.coral],
            child: Column(
              children: <Widget>[
                Text(
                  card!.type.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                ResponsivePartyText(
                  card!.text,
                  minFontSize: 28,
                  maxFontSize: 44,
                  maxLines: 6,
                ),
                const SizedBox(height: 12),
                Text('${card!.category} · Intensity ${card!.intensity}/3'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: resources.swapsRemaining == 0 ? null : _swap,
                  child: Text('SWAP · ${resources.swapsRemaining} LEFT'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _finishTurn(TruthDareTurnOutcome.completed),
                  child: const Text('DONE'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: resources.freeSkipsRemaining > 0
                ? () => _finishTurn(TruthDareTurnOutcome.skipped)
                : () => _finishTurn(TruthDareTurnOutcome.quit),
            child: Text(
              resources.freeSkipsRemaining > 0 ? 'SKIP FREE · 1 LEFT' : 'QUIT',
            ),
          ),
        ],
        if (session!.history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => setState(() => phase = _Phase.summary),
            icon: const Icon(Icons.receipt_long),
            label: const Text('END & VIEW SUMMARY'),
          ),
        ],
      ],
    );
  }

  Widget _summary() {
    final history = session!.history;
    final completed = history
        .where(
          (TruthDareTurnResult item) =>
              item.outcome == TruthDareTurnOutcome.completed,
        )
        .length;
    return ListView(
      key: const ValueKey<String>('truth-summary'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🎉', size: 104)),
        const SizedBox(height: 22),
        Text(
          '$completed of ${history.length} completed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        ...history.reversed.map(
          (item) => PartyCard(
            child: ListTile(
              leading: Text(
                item.card.type == 'truth' ? '❓' : '⚡',
                style: const TextStyle(fontSize: 26),
              ),
              title: Text(item.player.name),
              subtitle: Text(
                '${switch (item.outcome) {
                  TruthDareTurnOutcome.completed => 'DONE',
                  TruthDareTurnOutcome.skipped => 'FREE SKIP',
                  TruthDareTurnOutcome.quit => 'QUIT',
                }} · ${item.card.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                switch (item.outcome) {
                  TruthDareTurnOutcome.completed => Icons.check_circle,
                  TruthDareTurnOutcome.skipped => Icons.skip_next,
                  TruthDareTurnOutcome.quit => Icons.exit_to_app,
                },
                color: switch (item.outcome) {
                  TruthDareTurnOutcome.completed => PartyColors.green,
                  TruthDareTurnOutcome.skipped => PartyColors.yellow,
                  TruthDareTurnOutcome.quit => PartyColors.coral,
                },
              ),
            ),
          ),
        ),
        if (session!.playerStates.values.any((state) => !state.active)) ...[
          const SizedBox(height: 12),
          Text(
            'LEFT THE GAME: ${selected.where((player) => session!.playerStates[player.id]?.active == false).map((player) => player.name).join(', ')}',
            textAlign: TextAlign.center,
          ),
        ],
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  void _start() => setState(() {
    session = _engine.start(selected);
    used.clear();
    playerIndex = 0;
    card = null;
    phase = _Phase.play;
  });

  void _draw(String type) {
    final all = ref.read(gameDataProvider).truthOrDare;
    var pool = all
        .where(
          (TruthDareCard item) =>
              item.type == type &&
              (category == 'Mixed' || item.category == category),
        )
        .toList();
    final unused = pool
        .where((TruthDareCard item) => !used.contains(item.id))
        .toList();
    if (unused.isNotEmpty) pool = unused;
    setState(() {
      card = pool[ref.read(randomProvider).nextInt(pool.length)];
      used.add(card!.id);
    });
  }

  void _swap() {
    final player = selected[playerIndex];
    session = _engine.useSwap(session!, player.id);
    _draw(card!.type);
  }

  void _finishTurn(TruthDareTurnOutcome outcome) {
    final player = selected[playerIndex];
    session = _engine.recordTurn(
      session!,
      player: player,
      card: card!,
      outcome: outcome,
    );
    final nextId = _engine.nextPlayerId(
      session!,
      roster: selected,
      currentPlayerId: player.id,
      randomRotation: randomRotation,
      random: ref.read(randomProvider),
    );
    setState(() {
      if (nextId == null) {
        phase = _Phase.summary;
      } else {
        playerIndex = selected.indexWhere((player) => player.id == nextId);
      }
      card = null;
    });
  }
}
