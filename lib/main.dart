import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/data/game_data_repository.dart';
import 'core/services/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(<String>['Fredoka'], license);
  });
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  final storage = await AppStorage.create();
  final data = await GameDataRepository.load();
  runApp(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
      ],
      child: const PocketPartyApp(),
    ),
  );
}
