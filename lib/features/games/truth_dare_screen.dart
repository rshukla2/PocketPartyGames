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

enum _Phase { setup, play, summary }

class TruthDareScreen extends ConsumerStatefulWidget {
  const TruthDareScreen({super.key});
  @override
  ConsumerState<TruthDareScreen> createState() => _TruthDareScreenState();
}

class _TruthDareScreenState extends ConsumerState<TruthDareScreen> {
  _Phase phase = _Phase.setup;
  List<Player> selected = <Player>[];
  String category = 'Mixed';
  bool randomRotation = false;
  int playerIndex = 0;
  TruthDareCard? card;
  final history = <({Player player, TruthDareCard card, bool completed})>[];
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
        style: PartyGameStyle.truthDare,
        tone: switch (phase) {
          _Phase.play when category == 'Bold' => PartyScreenTone.secret,
          _Phase.play when card?.type == 'dare' => PartyScreenTone.action,
          _Phase.summary => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: switch (phase) {
          _Phase.setup => '200 original in-person cards',
          _Phase.play => '${selected[playerIndex].name}’s turn',
          _Phase.summary => '${history.length} turns played',
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
        onChanged: (List<Player> value) => selected = value,
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Card category'),
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
        onPressed: _start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('START GAME'),
      ),
    ],
  );

  Widget _play() {
    final player = selected[playerIndex];
    return ListView(
      key: ValueKey<String>('truth-play-${card?.id}-$playerIndex'),
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Center(child: PlayerAvatar(player: player, radius: 38)),
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
                  onPressed: _swap,
                  child: const Text('SWAP'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _complete(true),
                  child: const Text('DONE'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => _complete(false),
            child: const Text('Skip without penalty'),
          ),
        ],
        if (history.isNotEmpty) ...<Widget>[
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
    final completed = history.where((item) => item.completed).length;
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
                item.card.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                item.completed ? Icons.check_circle : Icons.skip_next,
                color: item.completed
                    ? PartyColors.green
                    : PartyColors.nearBlack,
              ),
            ),
          ),
        ),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  void _start() => setState(() {
    history.clear();
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

  void _swap() => _draw(card!.type);

  void _complete(bool completed) {
    history.add((
      player: selected[playerIndex],
      card: card!,
      completed: completed,
    ));
    setState(() {
      playerIndex = randomRotation
          ? ref.read(randomProvider).nextInt(selected.length)
          : (playerIndex + 1) % selected.length;
      card = null;
    });
  }
}
