import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/check_coverage.dart <lcov.info> <minimum-percent>',
    );
    exitCode = 64;
    return;
  }
  final lines = File(arguments[0]).readAsLinesSync();
  const measured = <String>[
    'lib/app/app_controller.dart',
    'lib/core/data/',
    'lib/core/models/',
    'lib/core/services/',
    'lib/features/nearby/lan_protocol.dart',
    'lib/features/nearby/nearby_imposter_session.dart',
    'lib/features/nearby/nearby_stop_timer_session.dart',
    'lib/features/games/imposter_engine.dart',
    'lib/features/games/stop_timer_engine.dart',
    'lib/features/games/trivia_engine.dart',
    'lib/features/games/truth_dare_engine.dart',
  ];
  var found = 0;
  var hit = 0;
  var include = false;
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      final source = line.substring(3);
      include = measured.any(source.contains);
    }
    if (include && line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    }
    if (include && line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }
  final percent = found == 0 ? 0 : hit * 100 / found;
  final minimum = double.parse(arguments[1]);
  stdout.writeln(
    'Critical logic line coverage: ${percent.toStringAsFixed(2)}% ($hit/$found)',
  );
  if (percent < minimum) {
    exitCode = 1;
  }
}
