import 'dart:developer';

import 'package:remove_unused_localizations/remove_unused_localizations.dart';

void main(List<String> arguments) {
  bool keepUnused = arguments.contains('--keep-unused');

  print('Running Localization Cleaner...');
  runLocalizationCleaner(keepUnused: keepUnused);
  print('Done.');
}
