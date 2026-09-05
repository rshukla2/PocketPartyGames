import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AppClock = DateTime Function();

final appClockProvider = Provider<AppClock>((Ref ref) => DateTime.now);
final randomProvider = Provider<Random>((Ref ref) => Random.secure());

class PartyFeedbackService {
  const PartyFeedbackService();

  Future<void> playAlert() => SystemSound.play(SystemSoundType.alert);
  Future<void> heavyImpact() => HapticFeedback.heavyImpact();
}

final partyFeedbackProvider = Provider<PartyFeedbackService>(
  (Ref ref) => const PartyFeedbackService(),
);
