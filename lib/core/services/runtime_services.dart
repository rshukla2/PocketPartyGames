import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AppClock = DateTime Function();

final appClockProvider = Provider<AppClock>((Ref ref) => DateTime.now);
final randomProvider = Provider<Random>((Ref ref) => Random.secure());
