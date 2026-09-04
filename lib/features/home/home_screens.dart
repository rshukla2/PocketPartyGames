import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/widgets/party_widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var index = 0;

  static const slides =
      <({String emoji, String title, String body, PartyGameStyle style})>[
        (
          emoji: '🎉',
          title: 'Party Games',
          body: 'No accounts, subscriptions, or cloud required.',
          style: PartyGameStyle.hub,
        ),
        (
          emoji: '🕵️',
          title: 'Imposter',
          body: 'Share a secret word, bluff confidently, discuss, and reveal the hidden imposters.',
          style: PartyGameStyle.imposter,
        ),
        (
          emoji: '⏱️',
          title: 'Stop the Timer',
          body: 'Train solo, battle with buzzers, or give one timer imposter a false target.',
          style: PartyGameStyle.stopTimer,
        ),
        (
          emoji: '⚡',
          title: 'Truth or Dare',
          body: 'Choose a Truth or Dare, pass the phone, and see how bold the party gets.',
          style: PartyGameStyle.truthDare,
        ),
        (
          emoji: '🎨',
          title: 'Pictionary',
          body: 'Sketch, guess, and bluff your way through Quick Draw and Drawing Imposter.',
          style: PartyGameStyle.pictionary,
        ),
        (
          emoji: '🔢',
          title: 'Guess My Number',
          body: 'Hold the phone up, ask yes-or-no questions, and race the optional timer.',
          style: PartyGameStyle.guessNumber,
        ),
        (
          emoji: '🎭',
          title: 'Act It Out',
          body: 'Act out wild prompts in Classic Charades or hide as the acting imposter.',
          style: PartyGameStyle.actItOut,
        ),
        (
          emoji: '5️⃣',
          title: '5-4-3-2-1',
          body: 'Name five things in five seconds, then descend through five rapid-fire levels.',
          style: PartyGameStyle.countdown,
        ),
        (
          emoji: '🧠',
          title: 'Trivia',
          body: 'Test your knowledge across several categories in solo, pass-and-play, or Nearby play.',
          style: PartyGameStyle.trivia,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final slide = slides[index];
    return Scaffold(
      body: PartyBackground(
        style: slide.style,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints viewport) =>
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewport.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: PartyColors.nearBlack,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: Image.asset(
                                      'assets/branding/icon_master.png',
                                      width: 38,
                                      height: 38,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'POCKET PARTY GAMES',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PartyStatusPill(
                                    label: '${index + 1}/${slides.length}',
                                    color: PartyPalettes.resolve(slide.style)
                                        .accent,
                                  ),
                                ],
                              ),
                              const Spacer(),
                              PartyPhaseSwitcher(
                                child: Column(
                                  key: ValueKey<int>(index),
                                  children: <Widget>[
                                    StickerBadge(
                                      emoji: slide.emoji,
                                      size: 142,
                                      background:
                                          slide.style ==
                                              PartyGameStyle.truthDare
                                          ? PartyColors.purple
                                          : PartyPalettes.resolve(slide.style)
                                                .accent,
                                    ),
                                    const SizedBox(height: 28),
                                    Text(
                                      slide.title.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      slide.body,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: PartyPalettes.resolve(
                                              slide.style,
                                            ).foreground.withValues(alpha: .9),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: <Widget>[
                                  if (index > 0)
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            setState(() => index--),
                                        child: const Text('Back'),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: FilledButton.icon(
                                      key: const Key('onboarding-next'),
                                      onPressed: () async {
                                        if (index < slides.length - 1) {
                                          setState(() => index++);
                                        } else {
                                          await ref
                                              .read(
                                                appControllerProvider.notifier,
                                              )
                                              .completeTutorial();
                                          if (context.mounted) {
                                            context.go('/players');
                                          }
                                        }
                                      },
                                      icon: Icon(
                                        index == slides.length - 1
                                            ? Icons.celebration
                                            : Icons.arrow_forward,
                                      ),
                                      label: Text(
                                        index == slides.length - 1
                                            ? 'LET’S PLAY'
                                            : 'NEXT',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  static const games =
      <
        ({
          String id,
          String title,
          String tagline,
          String emoji,
          PartyGameStyle style,
          bool nearby,
        })
      >[
        (
          id: 'trivia',
          title: 'TRIVIA',
          tagline: 'Solo · Versus · Browse questions',
          emoji: '🧠',
          style: PartyGameStyle.trivia,
          nearby: true,
        ),
        (
          id: 'imposter',
          title: 'IMPOSTER',
          tagline: 'Secret words · Bluffing · Deduction',
          emoji: '🕵️',
          style: PartyGameStyle.imposter,
          nearby: true,
        ),
        (
          id: 'stop-timer',
          title: 'STOP THE TIMER',
          tagline: 'Solo · Buzzer · Timer Imposter',
          emoji: '⏱️',
          style: PartyGameStyle.stopTimer,
          nearby: true,
        ),
        (
          id: 'truth-dare',
          title: 'TRUTH OR DARE',
          tagline: 'Truth · Dare · Chill to Bold',
          emoji: '⚡',
          style: PartyGameStyle.truthDare,
          nearby: false,
        ),
        (
          id: 'pictionary',
          title: 'PICTIONARY',
          tagline: 'Quick Draw · Drawing Imposter',
          emoji: '🎨',
          style: PartyGameStyle.pictionary,
          nearby: true,
        ),
        (
          id: 'guess-number',
          title: 'GUESS MY NUMBER',
          tagline: 'Forehead-style yes/no deduction',
          emoji: '🔢',
          style: PartyGameStyle.guessNumber,
          nearby: false,
        ),
        (
          id: 'act-it-out',
          title: 'ACT IT OUT',
          tagline: 'Classic Charades · Acting Imposter',
          emoji: '🎭',
          style: PartyGameStyle.actItOut,
          nearby: true,
        ),
        (
          id: 'countdown',
          title: '5-4-3-2-1',
          tagline: 'Rapid-fire · Score chase · Tiebreakers',
          emoji: '5️⃣',
          style: PartyGameStyle.countdown,
          nearby: false,
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      body: PartyBackground(
        style: PartyGameStyle.hub,
        palette: PartyPalettes.library,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: PartyColors.deepIndigo,
              title: const Text('POCKET PARTY GAMES'),
              actions: <Widget>[
                TextButton.icon(
                  onPressed: () => context.push('/players'),
                  icon: const Icon(Icons.groups_rounded),
                  label: Text('${state.players.length}'),
                ),
                IconButton(
                  onPressed: () => context.push('/settings'),
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'PICK A GAME.\nSTART SOME CHAOS.',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(color: PartyColors.white, height: .95),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints box) {
                            final columns = box.maxWidth >= 760 ? 2 : 1;
                            final textScale =
                                (MediaQuery.textScalerOf(context).scale(16) /
                                        16)
                                    .clamp(1.0, 2.0);
                            final cardExtent = 216 + ((textScale - 1) * 300);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: games.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 20,
                                    mainAxisExtent: cardExtent,
                                  ),
                              itemBuilder: (BuildContext context, int index) {
                                final game = games[index];
                                return GamePosterCard(
                                  style: game.style,
                                  emoji: game.emoji,
                                  title: game.title,
                                  tagline: game.tagline,
                                  stickerBackground:
                                      game.style == PartyGameStyle.truthDare
                                      ? PartyColors.purple
                                      : null,
                                  nearbyLabel: game.nearby
                                      ? (kIsWeb
                                            ? 'Nearby play in mobile app'
                                            : 'Play on nearby phones')
                                      : null,
                                  onTap: () => context.push('/game/${game.id}'),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayersScreen extends ConsumerStatefulWidget {
  const PlayersScreen({super.key});
  @override
  ConsumerState<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends ConsumerState<PlayersScreen> {
  late final TextEditingController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: ref.read(appControllerProvider.notifier).suggestedPlayerName(),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(
      appControllerProvider.select((AppState state) => state.players),
    );
    return PartyPage(
      title: 'Who’s playing?',
      style: PartyGameStyle.hub,
      subtitle: '${players.length}/20 players',
      showBack: players.isNotEmpty,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: <Widget>[
                PartyCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const Key('player-name'),
                            controller: controller,
                            maxLength: 16,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Player name',
                              errorText: error,
                              counterText: '',
                            ),
                            onChanged: (_) {
                              if (error != null) setState(() => error = null);
                            },
                            onSubmitted: players.length >= 20
                                ? null
                                : (_) => _add(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          key: const Key('add-player'),
                          onPressed: players.length >= 20 ? null : _add,
                          child: const Text('ADD'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...players.map(
                  (Player player) => PartyCard(
                    child: ListTile(
                      title: Text(
                        player.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${player.name}',
                        onPressed: () => ref
                            .read(appControllerProvider.notifier)
                            .removePlayer(player.id),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('pick-a-game'),
                onPressed: players.isEmpty ? null : () => context.go('/'),
                icon: const Icon(Icons.celebration_rounded),
                label: const Text('PICK A GAME'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final message = await ref
        .read(appControllerProvider.notifier)
        .addPlayer(controller.text);
    if (!mounted) return;
    setState(() => error = message);
    if (message == null) {
      final nextName = ref
          .read(appControllerProvider.notifier)
          .suggestedPlayerName();
      controller.value = TextEditingValue(
        text: nextName,
        selection: TextSelection.collapsed(offset: nextName.length),
      );
    }
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return PartyPage(
      title: 'Settings',
      style: PartyGameStyle.hub,
      subtitle: 'Feedback & local data',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PartyCard(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: state.settings.soundEnabled,
                  onChanged: ref.read(appControllerProvider.notifier).setSound,
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: const Text('Sound effects'),
                ),
                SwitchListTile(
                  value: state.settings.hapticsEnabled,
                  onChanged: ref
                      .read(appControllerProvider.notifier)
                      .setHaptics,
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Haptic feedback'),
                ),
              ],
            ),
          ),
          PartyCard(
            child: ListTile(
              leading: const Icon(Icons.timer_rounded),
              title: const Text('Solo Timer statistics'),
              subtitle: Text(
                '${state.soloStats.attempts} attempts · ${state.soloStats.nearPerfectCount} near perfect',
              ),
              trailing: Text(
                state.soloStats.bestErrorMs == null
                    ? '—'
                    : '±${(state.soloStats.bestErrorMs! / 1000).toStringAsFixed(2)}s',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.school_rounded),
            title: const Text('View tutorial'),
            onTap: () => context.push('/onboarding'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_rounded),
            title: const Text('Privacy'),
            subtitle: const Text('No accounts, analytics, ads, or cloud data.'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Pocket Party Games',
              applicationVersion: '1.0.0+1',
              applicationLegalese: 'MIT License · © 2026 Rishi Shukla',
              children: const <Widget>[
                Text(
                  'Players and settings remain on this device. Nearby sessions remain on your local Wi-Fi and disappear when the room ends.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () async {
              final confirmed =
                  await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text('Reset all local data?'),
                      content: const Text(
                        'This clears the roster, tutorial state, settings, and Solo Timer history.',
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (confirmed) {
                await ref.read(appControllerProvider.notifier).resetAll();
                if (context.mounted) context.go('/onboarding');
              }
            },
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('RESET ALL LOCAL DATA'),
          ),
        ],
      ),
    );
  }
}

class DataBrowserScreen extends ConsumerWidget {
  const DataBrowserScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    return PartyPage(
      title: 'Question Vault',
      style: PartyGameStyle.hub,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: data.trivia.length,
        itemBuilder: (BuildContext context, int index) {
          final item = data.trivia[index];
          return ExpansionTile(
            title: Text(item.question),
            subtitle: Text('${item.category} · ${item.difficulty}'),
            children: <Widget>[
              ListTile(
                title: Text(item.answer),
                subtitle: item.explanation == null
                    ? null
                    : Text(item.explanation!),
              ),
            ],
          );
        },
      ),
    );
  }
}
