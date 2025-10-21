import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

/// Scans the project for unused localization keys and removes them from `.arb` files.
void runLocalizationCleaner({bool keepUnused = false}) {
  final File yamlFile = File('l10n.yaml'); // Path to the l10n.yaml file
  if (!yamlFile.existsSync()) {
    print('✅ Error: l10n.yaml file not found!');
    return;
  }

  // Read & parse YAML
  final String yamlContent = yamlFile.readAsStringSync();
  final Map yamlData = loadYaml(yamlContent);

  // Extract values dynamically
  final String arbDir = yamlData['arb-dir'] as String;

  // Construct values
  final Directory localizationDir = Directory(arbDir);
  final Set<String> excludedFiles = {'$arbDir/app_localizations.dart'};

  // Read .arb file
  final List<File> localizationFiles =
      localizationDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .toList();

  if (localizationFiles.isEmpty) {
    print('✅ No .arb files found in ${localizationDir.path}');
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

  if (allKeys.isEmpty) {
    print('✅ No localization keys found in the provided ARB files.');
    return;
  }

  final Set<String> usedKeys = <String>{};
  final List<Directory> sourceDirectories = <Directory>[
    Directory('lib'),
    Directory('test'),
    Directory('integration_test'),
    Directory('bin'),
  ].where((Directory dir) => dir.existsSync()).toList();

  // Reg Exp to detect localization keys
  final String keysPattern = allKeys.map(RegExp.escape).join('|');
  final RegExp quickCheckRegex = RegExp(keysPattern);
  final String keyCapturePattern = '($keysPattern)(?=(?:\\s*\\()|\\b)';
  final RegExp accessRegex = RegExp(
    '(?:' // Start non-capturing group for all possible access patterns
        '(?:[a-zA-Z0-9_]+(?:\\?|!)?\\.)+' // e.g., `_appLocalizations.` or `cubit.appLocalizations.` with null-aware/assert
        '|'
        '[a-zA-Z0-9_]+\\.of\\(\\s*(?:context|AppNavigation\\.context|this\\.context|BuildContext\\s+\\w+)\\s*\\)\\s*(?:\\?|!)?\\s*\\.\\s*' // `of(context)!.key` or `?.key`
        '|'
        '[a-zA-Z0-9_]+\\.\\w+\\(\\s*\\)\\s*(?:\\?|!)?\\s*\\.\\s*' // `SomeClass.method().key` variants
        ')'
        '$keyCapturePattern',
    multiLine: true,
    dotAll: true, // Makes `.` match newlines (crucial for multi-line cases)
  );
  final RegExp rawStringRegex = RegExp(
    '(?:r|R)?([\'"]{1,3})($keysPattern)\\1', // Matches string literals that contain only the key
    multiLine: true,
    dotAll: true,
  );

  // Scan Dart files for key usage
  for (final Directory sourceDir in sourceDirectories) {
    for (final FileSystemEntity entity in sourceDir.listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          excludedFiles.contains(entity.path)) {
        continue;
      }

      final String content = entity.readAsStringSync();

      // Quick pre-check: skip files that don't contain any key substring
      if (!quickCheckRegex.hasMatch(content)) continue;

      for (final Match match in accessRegex.allMatches(content)) {
        usedKeys.add(match.group(1)!); // Capture only the key
      }

      for (final Match match in rawStringRegex.allMatches(content)) {
        usedKeys.add(match.group(2)!);
      }
    }
  }

  // Determine unused keys
  final Set<String> unusedKeys = allKeys.difference(usedKeys);
  if (unusedKeys.isEmpty) {
    print('✅ No unused localization keys found.');
    return;
  }

  print("✅ Unused keys found: ${unusedKeys.join(', ')}");

  if (keepUnused) {
    // Keep unused keys to a file instead of deleting them
    final File unusedKeysFile = File('unused_localization_keys.txt');
    unusedKeysFile.writeAsStringSync(unusedKeys.join('\n'));
    print('✅ Unused keys saved to ${unusedKeysFile.path}');
  } else {
    // Remove unused keys from all .arb files
    for (final MapEntry<File, Set<String>> entry in fileKeyMap.entries) {
      final File file = entry.key;
      final Set<String> keys = entry.value;
      final Map<String, dynamic> data =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;

      bool updated = false;
      for (final key in keys) {
        if (unusedKeys.contains(key)) {
          data.remove(key);
          data.remove('@$key');
          updated = true;
        }
      }

      if (updated) {
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(data),
        );
        print('✅ Updated ${file.path}, removed unused keys.');
      }
    }
    print('✅ Unused keys successfully removed.');
  }
}
