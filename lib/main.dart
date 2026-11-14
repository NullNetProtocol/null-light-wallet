import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/wallet_core.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final core = await loadCore();
  final settings = await AppSettings.load();
  runApp(NullWalletApp(core: core, settings: settings));
}
