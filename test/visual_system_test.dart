import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';

void main() {
  test('every game and screen tone uses an accessible foreground', () {
    for (final style in PartyGameStyle.values) {
      for (final tone in PartyScreenTone.values) {
        final palette = PartyPalettes.resolve(style, tone);
        expect(
          _contrast(palette.background, palette.foreground),
          greaterThanOrEqualTo(4.5),
          reason: '${style.name}/${tone.name} foreground contrast',
        );
        expect(
          _contrast(palette.surface, palette.onSurface),
          greaterThanOrEqualTo(4.5),
          reason: '${style.name}/${tone.name} surface contrast',
        );
      }
    }
  });

  test('each game has its own authoritative standard background', () {
    final backgrounds = <PartyGameStyle, Color>{
      for (final style in PartyGameStyle.values)
        style: PartyPalettes.resolve(style).background,
    };
    expect(backgrounds[PartyGameStyle.hub], PartyColors.purple);
    expect(backgrounds[PartyGameStyle.trivia], PartyColors.blue);
    expect(backgrounds[PartyGameStyle.stopTimer], PartyColors.orange);
    expect(backgrounds[PartyGameStyle.truthDare], PartyColors.pink);
    expect(backgrounds[PartyGameStyle.pictionary], PartyColors.cyan);
    expect(backgrounds[PartyGameStyle.guessNumber], PartyColors.green);
    expect(backgrounds[PartyGameStyle.countdown], PartyColors.coral);
  });

  testWidgets('background exposes the requested game and phase palette', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPartyTheme(),
        home: const PartyBackground(
          style: PartyGameStyle.pictionary,
          tone: PartyScreenTone.action,
          child: SizedBox.expand(),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.byKey(const ValueKey<String>('party-background-pictionary-action')),
    );
    expect(material.color, PartyColors.blue);
  });

  testWidgets('party controls keep large tactile targets', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPartyTheme(),
        home: PartyBackground(
          child: Center(
            child: FilledButton(
              onPressed: () {},
              child: const Text('LET’S PLAY'),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(56));
    expect(size.width, greaterThanOrEqualTo(48));
    final semantics = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('party sliders stay visible on every game background', (
    WidgetTester tester,
  ) async {
    for (final style in PartyGameStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPartyTheme(),
          home: PartyBackground(
            style: style,
            child: PartySlider(
              value: 2,
              min: 1,
              max: 3,
              divisions: 2,
              label: '2',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      final sliderTheme = tester.widget<SliderTheme>(find.byType(SliderTheme));
      final background = PartyPalettes.resolve(style).background;
      expect(
        _contrast(sliderTheme.data.activeTrackColor!, background),
        greaterThanOrEqualTo(2),
        reason: '${style.name} active slider track',
      );
      expect(sliderTheme.data.inactiveTrackColor, PartyColors.white);
      expect(sliderTheme.data.thumbColor, isNot(background));
    }
  });

  testWidgets('phase transitions honor reduced motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPartyTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PartyBackground(
            child: PartyPhaseSwitcher(child: Text('READY')),
          ),
        ),
      ),
    );
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });

  testWidgets('long prompts remain usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPartyTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: PartyPage(
            title: 'Trivia',
            subtitle: 'Question 10 of 10',
            style: PartyGameStyle.trivia,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const PartyCard(
                  padding: EdgeInsets.all(20),
                  child: ResponsivePartyText(
                    'Which famously complicated party-game question still has to fit comfortably on this screen?',
                    minFontSize: 28,
                    maxFontSize: 44,
                    maxLines: 8,
                    color: PartyColors.nearBlack,
                  ),
                ),
                FilledButton(
                  onPressed: () {},
                  child: const Text('REVEAL ANSWER'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('REVEAL ANSWER'), findsOneWidget);
  });

  testWidgets('the bundled theme uses Fredoka for display and body copy', (
    WidgetTester tester,
  ) async {
    final theme = buildPartyTheme();
    expect(theme.textTheme.displayLarge?.fontFamily, 'Fredoka');
    expect(theme.textTheme.bodyLarge?.fontFamily, 'Fredoka');
    expect(theme.textTheme.displayLarge?.fontWeight, FontWeight.w800);
    expect(theme.textTheme.bodyLarge?.fontWeight, FontWeight.w600);
  });

  testWidgets('full player names remain readable at supported text scales', (
    WidgetTester tester,
  ) async {
    const player = Player(
      id: 'long-name',
      name: 'Alexandria Rose',
      colorIndex: 2,
    );
    for (final scale in <double>[1, 1.3, 2]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPartyTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Center(child: PlayerNameBadge(player: player)),
            ),
          ),
        ),
      );
      expect(find.text('Alexandria Rose'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + .05) / (darker.computeLuminance() + .05);
}
