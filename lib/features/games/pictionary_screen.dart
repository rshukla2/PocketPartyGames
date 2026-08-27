import 'dart:async';

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

enum _DrawMode { quick, imposter }

enum _DrawPhase { setup, handoff, draw, review, result }

class PictionaryScreen extends ConsumerStatefulWidget {
  const PictionaryScreen({super.key});

  @override
  ConsumerState<PictionaryScreen> createState() => _PictionaryScreenState();
}

class _PictionaryScreenState extends ConsumerState<PictionaryScreen> {
  _DrawMode mode = _DrawMode.quick;
  _DrawPhase phase = _DrawPhase.setup;
  List<Player> players = <Player>[];
  int turn = 0;
  int secondsPerTurn = 60;
  int seconds = 60;
  int rounds = 2;
  String category = 'All';
  late PictionaryPrompt prompt;
  String? imposterId;
  Timer? timer;
  final scores = <String, int>{};
  final used = <String>{};
  final canvasKey = GlobalKey<DrawingCanvasState>();

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (players.isEmpty) players = List<Player>.from(app.players);
    return PopScope(
      canPop: phase == _DrawPhase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Pictionary',
        style: PartyGameStyle.pictionary,
        tone: switch (phase) {
          _DrawPhase.handoff when mode == _DrawMode.imposter =>
            PartyScreenTone.secret,
          _DrawPhase.draw || _DrawPhase.review => PartyScreenTone.action,
          _DrawPhase.result => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: phase == _DrawPhase.setup
            ? '194 prompts · Canvas included'
            : '${players[turn % players.length].name} draws',
        maxWidth: 760,
        child: PartyPhaseSwitcher(child: _body(app)),
      ),
    );
  }

  Widget _body(AppState app) => switch (phase) {
    _DrawPhase.setup => _setup(app),
    _DrawPhase.handoff => _handoff(),
    _DrawPhase.draw => _draw(),
    _DrawPhase.review => _review(),
    _DrawPhase.result => _result(),
  };

  Widget _setup(AppState app) {
    final categories = <String>{
      'All',
      ...ref
          .read(gameDataProvider)
          .pictionary
          .map((PictionaryPrompt p) => p.category),
    }.toList()..sort();
    return ListView(
      key: const ValueKey<String>('pictionary-setup'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SegmentedButton<_DrawMode>(
          segments: const <ButtonSegment<_DrawMode>>[
            ButtonSegment<_DrawMode>(
              value: _DrawMode.quick,
              icon: Icon(Icons.brush),
              label: Text('Quick Draw'),
            ),
            ButtonSegment<_DrawMode>(
              value: _DrawMode.imposter,
              icon: Icon(Icons.visibility_off),
              label: Text('Drawing Imposter'),
            ),
          ],
          selected: <_DrawMode>{mode},
          onSelectionChanged: (Set<_DrawMode> value) =>
              setState(() => mode = value.first),
        ),
        const SizedBox(height: 16),
        Text(
          mode == _DrawMode.quick
              ? 'Take turns drawing while everyone else guesses. Award the point on this phone.'
              : 'One player receives only the category. Compare the drawings, then find the imposter.',
        ),
        const SizedBox(height: 18),
        PlayerChips(
          players: app.players,
          minimum: mode == _DrawMode.imposter ? 3 : 2,
          onChanged: (List<Player> value) => players = value,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Prompt category'),
          items: categories
              .map(
                (String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (String? value) =>
              setState(() => category = value ?? 'All'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: secondsPerTurn,
          decoration: const InputDecoration(labelText: 'Drawing time'),
          items: const <int>[30, 45, 60, 90]
              .map(
                (int value) => DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value seconds'),
                ),
              )
              .toList(),
          onChanged: (int? value) => secondsPerTurn = value ?? 60,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: rounds,
          decoration: const InputDecoration(labelText: 'Rounds per player'),
          items: const <int>[1, 2, 3]
              .map(
                (int value) =>
                    DropdownMenuItem<int>(value: value, child: Text('$value')),
              )
              .toList(),
          onChanged: (int? value) => rounds = value ?? 2,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('START LOCAL GAME'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/nearby?game=pictionary'),
          icon: const Icon(Icons.wifi),
          label: const Text('PLAY NEARBY'),
        ),
      ],
    );
  }

  Widget _handoff() {
    final player = players[turn % players.length];
    final isImposter = player.id == imposterId;
    return Padding(
      key: ValueKey<String>('draw-handoff-$turn'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerAvatar(player: player, radius: 46),
          const SizedBox(height: 16),
          Text(
            'Pass to ${player.name}',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Keep the screen private, then reveal your prompt.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: Text(
                  isImposter ? 'You are the drawing imposter' : prompt.word,
                ),
                content: Text(
                  isImposter
                      ? 'You only know the category: ${prompt.category}. Blend in.'
                      : prompt.hint ??
                            'Draw it without writing words or numbers.',
                ),
                actions: <Widget>[
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .primary,
                      foregroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .onPrimary,
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _beginDraw();
                    },
                    child: const Text('I’VE GOT IT'),
                  ),
                ],
              ),
            ),
            child: const Text('REVEAL MY PROMPT'),
          ),
        ],
      ),
    );
  }

  Widget _draw() => Column(
    key: ValueKey<String>('drawing-$turn'),
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Text(
              '$seconds s',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Undo stroke',
              onPressed: () => canvasKey.currentState?.undo(),
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Clear canvas',
              onPressed: () => canvasKey.currentState?.clear(),
              icon: const Icon(Icons.delete_outline),
            ),
            FilledButton.tonal(
              onPressed: _finishDrawing,
              child: const Text('DONE'),
            ),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DrawingCanvas(key: canvasKey),
        ),
      ),
    ],
  );

  Widget _review() => ListView(
    key: ValueKey<String>('draw-review-$turn'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text(
        'The prompt was…',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        prompt.word,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 18),
      AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: CustomPaint(
            painter: StrokePainter(
              canvasKey.currentState?.strokes ?? const <DrawStroke>[],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (mode == _DrawMode.quick) ...<Widget>[
        FilledButton.icon(
          onPressed: () => _score(true),
          icon: const Icon(Icons.check),
          label: const Text('GUESSED CORRECTLY · +1'),
        ),
        OutlinedButton(
          onPressed: () => _score(false),
          child: const Text('NO CORRECT GUESS'),
        ),
      ] else
        FilledButton(
          onPressed: _nextTurn,
          child: Text(
            turn + 1 >= players.length * rounds
                ? 'REVEAL IMPOSTER'
                : 'NEXT DRAWER',
          ),
        ),
    ],
  );

  Widget _result() {
    if (mode == _DrawMode.imposter) {
      final imposter = players.firstWhere((Player p) => p.id == imposterId);
      return ListView(
        key: const ValueKey<String>('drawing-imposter-result'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Center(child: StickerBadge(emoji: '🕵️', size: 104)),
          const SizedBox(height: 22),
          Text(
            '${imposter.name} was the drawing imposter',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'The shared prompt was “${prompt.word}”.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
          TextButton(
            onPressed: () => setState(() => phase = _DrawPhase.setup),
            child: const Text('CHANGE SETUP'),
          ),
        ],
      );
    }
    return ListView(
      key: const ValueKey<String>('quick-draw-result'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🎨', size: 104)),
        const SizedBox(height: 22),
        ScoreBoard(players: players, scores: scores),
        const SizedBox(height: 16),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        TextButton(
          onPressed: () => setState(() => phase = _DrawPhase.setup),
          child: const Text('CHANGE SETUP'),
        ),
      ],
    );
  }

  void _start() {
    if (players.length < (mode == _DrawMode.imposter ? 3 : 2)) return;
    final pool = ref
        .read(gameDataProvider)
        .pictionary
        .where(
          (PictionaryPrompt p) => category == 'All' || p.category == category,
        )
        .toList();
    final random = ref.read(randomProvider);
    prompt = pool[random.nextInt(pool.length)];
    imposterId = mode == _DrawMode.imposter
        ? players[random.nextInt(players.length)].id
        : null;
    scores
      ..clear()
      ..addEntries(players.map((Player p) => MapEntry<String, int>(p.id, 0)));
    used.clear();
    turn = 0;
    setState(() => phase = _DrawPhase.handoff);
  }

  void _beginDraw() {
    timer?.cancel();
    seconds = secondsPerTurn;
    setState(() => phase = _DrawPhase.draw);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => canvasKey.currentState?.clear(),
    );
    timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
      if (!mounted) return;
      if (seconds <= 1) {
        value.cancel();
        _finishDrawing();
      } else {
        setState(() => seconds--);
      }
    });
  }

  void _finishDrawing() {
    timer?.cancel();
    if (phase == _DrawPhase.draw) setState(() => phase = _DrawPhase.review);
  }

  void _score(bool correct) {
    if (correct) {
      scores[players[turn % players.length].id] =
          (scores[players[turn % players.length].id] ?? 0) + 1;
    }
    _nextTurn();
  }

  void _nextTurn() {
    turn++;
    if (turn >= players.length * rounds) {
      setState(() => phase = _DrawPhase.result);
      return;
    }
    if (mode == _DrawMode.quick) {
      final pool = ref
          .read(gameDataProvider)
          .pictionary
          .where(
            (PictionaryPrompt p) => category == 'All' || p.category == category,
          )
          .toList();
      final available = pool
          .where((PictionaryPrompt p) => !used.contains(p.id))
          .toList();
      prompt =
          (available.isEmpty ? pool : available)[ref
              .read(randomProvider)
              .nextInt((available.isEmpty ? pool : available).length)];
      used.add(prompt.id);
    }
    setState(() => phase = _DrawPhase.handoff);
  }
}

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key});

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<DrawStroke> strokes = <DrawStroke>[];
  List<DrawPoint> current = <DrawPoint>[];
  Color color = PartyColors.nearBlack;
  double width = 5;

  void undo() => setState(() {
    if (strokes.isNotEmpty) strokes.removeLast();
  });
  void clear() => setState(() {
    strokes.clear();
    current = <DrawPoint>[];
  });

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: Colors.white,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (DragStartDetails d) =>
                        _start(d.localPosition, constraints.biggest),
                    onPanUpdate: (DragUpdateDetails d) =>
                        _add(d.localPosition, constraints.biggest),
                    onPanEnd: (_) => _end(),
                    child: Semantics(
                      label: 'Drawing canvas',
                      hint: 'Drag one finger to draw',
                      child: CustomPaint(
                        painter: StrokePainter(<DrawStroke>[
                          ...strokes,
                          if (current.isNotEmpty)
                            DrawStroke(
                              colorValue: color.toARGB32(),
                              width: width,
                              points: current,
                            ),
                        ]),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children:
            <Color>[
                  PartyColors.nearBlack,
                  PartyColors.coral,
                  PartyColors.blue,
                  PartyColors.green,
                  PartyColors.orange,
                ]
                .map(
                  (Color value) => Semantics(
                    label:
                        'Use ${value == PartyColors.nearBlack ? 'black' : 'color'} pen',
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => color = value),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: value,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == value
                                ? Colors.white
                                : Colors.transparent,
                            width: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
    ],
  );

  DrawPoint _normalize(Offset point, Size size) => DrawPoint(
    (point.dx / size.width).clamp(0, 1),
    (point.dy / size.height).clamp(0, 1),
  );
  void _start(Offset point, Size size) =>
      setState(() => current = <DrawPoint>[_normalize(point, size)]);
  void _add(Offset point, Size size) => setState(
    () => current = <DrawPoint>[...current, _normalize(point, size)],
  );
  void _end() => setState(() {
    if (current.isNotEmpty) {
      strokes.add(
        DrawStroke(
          colorValue: color.toARGB32(),
          width: width,
          points: List<DrawPoint>.from(current),
        ),
      );
    }
    current = <DrawPoint>[];
  });
}

class StrokePainter extends CustomPainter {
  const StrokePainter(this.strokes);
  final List<DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(
          stroke.points.first.x * size.width,
          stroke.points.first.y * size.height,
        );
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
