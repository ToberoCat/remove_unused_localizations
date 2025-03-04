import 'dart:convert';
import 'dart:developer';
import 'dart:io';

void runLocalizationCleaner() {
  final Directory localizationDir = Directory(
    'lib/l10n',
  ); // Adjust path if needed
  final Set<String> excludedFiles = {'lib/l10n/app_localizations.dart'};

  // Get all .arb files dynamically (handles all languages)
  final List<File> localizationFiles =
      localizationDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .toList();

  if (localizationFiles.isEmpty) {
    log('No .arb files found in ${localizationDir.path}');
    return;
  }

  final Set<String> allKeys = <String>{};
  final Map<File, Set<String>> fileKeyMap = <File, Set<String>>{};

  // Read all keys from ARB files
  for (final File file in localizationFiles) {
    final Map<String, dynamic> data =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final Set<String> keys =
        data.keys.where((key) => !key.startsWith('@')).toSet();
    allKeys.addAll(keys);
    fileKeyMap[file] = keys;
  }

  final Set<String> usedKeys = <String>{};
  final Directory libDir = Directory('lib');

  // Scan Dart files, excluding specified ones
  for (final FileSystemEntity file in libDir.listSync(recursive: true)) {
    if (file is File &&
        file.path.endsWith('.dart') &&
        !excludedFiles.contains(file.path)) {
      final String content = file.readAsStringSync();
      for (final String key in allKeys) {
        // Check key usage with different patterns
        if (RegExp(
              r'\blocalizations\.' + RegExp.escape(key) + r'\b',
            ).hasMatch(content) ||
            RegExp(
              r'\bS\.of\(context\)\.' + RegExp.escape(key) + r'\b',
            ).hasMatch(content) ||
            RegExp(
              r'\bAppLocalizations\.of\(context\)!\.' +
                  RegExp.escape(key) +
                  r'\b',
            ).hasMatch(content)) {
          usedKeys.add(key);
        }
      }
    }
  }

  // Determine truly unused keys
  final Set<String> unusedKeys = allKeys.difference(usedKeys);
  if (unusedKeys.isEmpty) {
    log('No unused localization keys found.');
    return;
  }

  log("Unused keys found: ${unusedKeys.join(', ')}");

  // Remove only unused keys from all .arb files
  for (final MapEntry<File, Set<String>> entry in fileKeyMap.entries) {
    final File file = entry.key;
    final Set<String> keys = entry.value;
    final Map<String, dynamic> data =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;

    bool updated = false;
    for (final key in keys) {
      if (unusedKeys.contains(key)) {
        data.remove(key);
        data.remove('@$key'); // Remove metadata too
        updated = true;
      }
    }

    if (updated) {
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      log('Updated ${file.path}, removed unused keys.');
    }
  }

  log('✅ Unused keys successfully removed from all languages.');
}
