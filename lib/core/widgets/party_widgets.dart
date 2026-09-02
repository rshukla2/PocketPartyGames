import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../models/app_models.dart';

class PartyVisualScope extends InheritedWidget {
  const PartyVisualScope({
    required this.style,
    required this.tone,
    required this.palette,
    required super.child,
    super.key,
  });

  final PartyGameStyle style;
  final PartyScreenTone tone;
  final PartyPalette palette;

  static PartyVisualScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PartyVisualScope>();
    assert(scope != null, 'PartyVisualScope is missing above this widget.');
    return scope!;
  }

  static PartyVisualScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PartyVisualScope>();

  @override
  bool updateShouldNotify(PartyVisualScope oldWidget) =>
      style != oldWidget.style || tone != oldWidget.tone;
}

extension PartyBuildContext on BuildContext {
  PartyPalette get partyPalette =>
      PartyVisualScope.maybeOf(this)?.palette ??
      PartyPalettes.resolve(PartyGameStyle.hub);
}

class PartyBackground extends StatelessWidget {
  const PartyBackground({
    required this.child,
    this.style = PartyGameStyle.hub,
    this.tone = PartyScreenTone.standard,
    this.safeArea = true,
    super.key,
  });

  final Widget child;
  final PartyGameStyle style;
  final PartyScreenTone tone;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final palette = PartyPalettes.resolve(style, tone);
    final foreground = TextStyle(
      color: palette.foreground,
      fontFamily: 'Fredoka',
      fontWeight: FontWeight.w500,
    );
    final content = safeArea ? SafeArea(child: child) : child;

    return Theme(
      data: buildPartyTheme(palette: palette),
      child: PartyVisualScope(
        style: style,
        tone: tone,
        palette: palette,
        child: Material(
          key: ValueKey<String>('party-background-${style.name}-${tone.name}'),
          color: palette.background,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PartyBackdropPainter(palette: palette),
                  ),
                ),
              ),
              DefaultTextStyle.merge(
                style: foreground,
                child: IconTheme(
                  data: IconThemeData(color: palette.foreground),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PartyPage extends StatelessWidget {
  const PartyPage({
    required this.title,
    required this.child,
    required this.style,
    this.tone = PartyScreenTone.standard,
    this.subtitle,
    this.actions,
    this.showBack = true,
    this.centerTitle = false,
    this.maxWidth = 560,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool showBack;
  final bool centerTitle;
  final double maxWidth;
  final PartyGameStyle style;
  final PartyScreenTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = PartyPalettes.resolve(style, tone);
    final textScale =
        (MediaQuery.maybeTextScalerOf(context)?.scale(16) ?? 16) / 16;
    return Scaffold(
      backgroundColor: palette.background,
      body: PartyBackground(
        style: style,
        tone: tone,
        child: Column(
          children: <Widget>[
            AppBar(
              centerTitle: centerTitle,
              toolbarHeight: subtitle == null
                  ? 64
                  : 64 + ((textScale - 1).clamp(0, 1) * 30),
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              leading: showBack
                  ? IconButton(
                      tooltip: 'Go back',
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
              title: Column(
                crossAxisAlignment: centerTitle
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.foreground.withValues(alpha: .82),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              actions: actions,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartyCard extends StatelessWidget {
  const PartyCard({
    required this.child,
    this.padding,
    this.margin = const EdgeInsets.symmetric(vertical: 5),
    this.color,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets margin;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.partyPalette;
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: Container(
        margin: margin.copyWith(bottom: margin.bottom + 6),
        decoration: BoxDecoration(
          color: color ?? palette.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: <BoxShadow>[
            BoxShadow(color: palette.shadow, offset: const Offset(0, 7)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: palette.onSurface, fontFamily: 'Fredoka'),
              child: IconTheme(
                data: IconThemeData(color: palette.onSurface),
                child: ListTileTheme.merge(
                  textColor: palette.onSurface,
                  iconColor: palette.onSurface,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GradientCard extends StatelessWidget {
  const GradientCard({
    required this.colors,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.foregroundColor = PartyColors.white,
    super.key,
  });

  final List<Color> colors;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: context.partyPalette.shadow,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(28),
        ),
        child: InkWell(
          onTap: onTap,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor, fontFamily: 'Fredoka'),
            child: IconTheme(
              data: IconThemeData(color: foregroundColor),
              child: ListTileTheme.merge(
                textColor: foregroundColor,
                iconColor: foregroundColor,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class GamePosterCard extends StatelessWidget {
  const GamePosterCard({
    required this.style,
    required this.emoji,
    required this.title,
    required this.tagline,
    required this.onTap,
    this.nearbyLabel,
    this.stickerBackground,
    super.key,
  });

  final PartyGameStyle style;
  final String emoji;
  final String title;
  final String tagline;
  final String? nearbyLabel;
  final Color? stickerBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PartyPalettes.resolve(style);
    return TactileSurface(
      onTap: onTap,
      semanticLabel: '$title. $tagline',
      child: Container(
        constraints: const BoxConstraints(minHeight: 188),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: PartyColors.nearBlack, offset: Offset(0, 8)),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -26,
              top: -42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: .35),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 140, height: 140),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                StickerBadge(
                  emoji: emoji,
                  background: stickerBackground ?? palette.accent,
                  size: 78,
                  rotation: -.045,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: palette.foreground),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 23,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tagline,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (nearbyLabel != null) ...<Widget>[
                          const SizedBox(height: 10),
                          PartyStatusPill(
                            label: nearbyLabel!,
                            color: palette.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 34,
                  color: palette.foreground,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StickerBadge extends StatelessWidget {
  const StickerBadge({
    required this.emoji,
    this.size = 116,
    this.background = PartyColors.white,
    this.rotation = -.035,
    super.key,
  });

  final String emoji;
  final double size;
  final Color background;
  final double rotation;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: rotation,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: PartyColors.nearBlack, width: 3),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: PartyColors.nearBlack, offset: Offset(6, 7)),
        ],
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * .5)),
    ),
  );
}

class PartyHero extends StatelessWidget {
  const PartyHero({
    required this.emoji,
    required this.title,
    this.body,
    this.badgeColor,
    super.key,
  });

  final String emoji;
  final String title;
  final String? body;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.partyPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        StickerBadge(emoji: emoji, background: badgeColor ?? palette.accent),
        const SizedBox(height: 28),
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(color: palette.foreground),
        ),
        if (body != null) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: palette.foreground.withValues(alpha: .9)),
          ),
        ],
      ],
    );
  }
}

class PartyStatusPill extends StatelessWidget {
  const PartyStatusPill({
    required this.label,
    this.color = PartyColors.white,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: PartyColors.nearBlack),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PartyColors.nearBlack,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
        ),
      ],
    ),
  );
}

class ResponsivePartyText extends StatelessWidget {
  const ResponsivePartyText(
    this.text, {
    this.minFontSize = 32,
    this.maxFontSize = 100,
    this.maxLines = 3,
    this.textAlign = TextAlign.center,
    this.color,
    super.key,
  });

  final String text;
  final double minFontSize;
  final double maxFontSize;
  final int maxLines;
  final TextAlign textAlign;
  final Color? color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final responsiveSize = (width / math.max(5, text.length * .22)).clamp(
        minFontSize,
        maxFontSize,
      );
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.fade,
        textAlign: textAlign,
        style: TextStyle(
          color: color ?? context.partyPalette.foreground,
          fontSize: responsiveSize,
          height: .98,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
      );
    },
  );
}

class PartyPhaseSwitcher extends StatelessWidget {
  const PartyPhaseSwitcher({
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      transitionBuilder: (Widget child, Animation<double> animation) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class TactileSurface extends StatefulWidget {
  const TactileSurface({
    required this.child,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<TactileSurface> createState() => _TactileSurfaceState();
}

class _TactileSurfaceState extends State<TactileSurface> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => pressed = true),
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        child: AnimatedScale(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 90),
          scale: pressed ? .975 : 1,
          child: AnimatedSlide(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            offset: pressed ? const Offset(0, .018) : Offset.zero,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({required this.player, this.radius = 22, super.key});

  final Player player;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: PartyColors
          .playerColors[player.colorIndex % PartyColors.playerColors.length],
      shape: BoxShape.circle,
      border: Border.all(color: PartyColors.nearBlack, width: 2.5),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: PartyColors.nearBlack, offset: Offset(2, 3)),
      ],
    ),
    child: Text(
      player.name.characters.first.toUpperCase(),
      style: TextStyle(
        color: PartyColors.white,
        fontWeight: FontWeight.w800,
        fontSize: radius * .8,
      ),
    ),
  );
}

class PlayerChips extends StatefulWidget {
  const PlayerChips({
    required this.players,
    required this.onChanged,
    this.minimum = 2,
    super.key,
  });

  final List<Player> players;
  final ValueChanged<List<Player>> onChanged;
  final int minimum;

  @override
  State<PlayerChips> createState() => _PlayerChipsState();
}

class _PlayerChipsState extends State<PlayerChips> {
  late final Set<String> selected = widget.players
      .map((Player player) => player.id)
      .toSet();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: widget.players.map((Player player) {
      final active = selected.contains(player.id);
      return FilterChip(
        selected: active,
        avatar: PlayerAvatar(player: player, radius: 14),
        label: Text(player.name),
        onSelected: (bool value) {
          if (!value && selected.length <= widget.minimum) return;
          setState(
            () => value ? selected.add(player.id) : selected.remove(player.id),
          );
          widget.onChanged(
            widget.players
                .where((Player item) => selected.contains(item.id))
                .toList(),
          );
        },
      );
    }).toList(),
  );
}

Future<bool> confirmLeaveGame(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Text('👋', style: TextStyle(fontSize: 44)),
        title: const Text('LEAVE ACTIVE GAME?'),
        content: const Text('Current round progress will be lost.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('STAY'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PartyColors.coral,
              foregroundColor: PartyColors.nearBlack,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('LEAVE GAME'),
          ),
        ],
      ),
    ) ??
    false;

class ScoreBoard extends StatelessWidget {
  const ScoreBoard({required this.players, required this.scores, super.key});

  final List<Player> players;
  final Map<String, int> scores;

  @override
  Widget build(BuildContext context) {
    final ranked = List<Player>.from(players)
      ..sort(
        (Player a, Player b) =>
            (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0),
      );
    return Column(
      children: ranked.indexed.map((item) {
        final (index, player) = item;
        return PartyCard(
          child: ListTile(
            leading: Text(
              index == 0 ? '🏆' : '#${index + 1}',
              style: const TextStyle(
                color: PartyColors.nearBlack,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            title: Text(
              player.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: Text(
              '${scores[player.id] ?? 0} pts',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: PartyColors.nearBlack),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class PartyBackdropPainter extends CustomPainter {
  PartyBackdropPainter({required this.palette});

  final PartyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final soft = Paint()..color = palette.foreground.withValues(alpha: .08);
    final accent = Paint()..color = palette.accent.withValues(alpha: .18);

    canvas.drawCircle(
      Offset(size.width * .9, size.height * .14),
      shortest * .18,
      soft,
    );
    canvas.drawCircle(
      Offset(size.width * .05, size.height * .76),
      shortest * .12,
      accent,
    );

    canvas.save();
    canvas.translate(size.width * .12, size.height * .16);
    canvas.rotate(-.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: shortest * .2,
          height: shortest * .07,
        ),
        const Radius.circular(22),
      ),
      soft,
    );
    canvas.restore();

    _drawStar(
      canvas,
      Offset(size.width * .84, size.height * .78),
      shortest * .055,
      accent,
    );
    _drawStar(
      canvas,
      Offset(size.width * .18, size.height * .42),
      shortest * .032,
      soft,
    );
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var index = 0; index < 8; index++) {
      final angle = -math.pi / 2 + (math.pi / 4 * index);
      final pointRadius = index.isEven ? radius : radius * .36;
      final point = Offset(
        center.dx + math.cos(angle) * pointRadius,
        center.dy + math.sin(angle) * pointRadius,
      );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(PartyBackdropPainter oldDelegate) =>
      palette.background != oldDelegate.palette.background ||
      palette.foreground != oldDelegate.palette.foreground ||
      palette.accent != oldDelegate.palette.accent;
}
