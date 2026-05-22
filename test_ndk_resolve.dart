import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:logging/logging.dart';

void main() async {
  hierarchicalLoggingEnabled = true;
  final logger = Logger('')
    ..level = Level.ALL
    ..onRecord.listen((record) {
      if (record.message.isNotEmpty) print('${record.level}: ${record.message}');
    });

  // Test 1: Direct directory check
  final ndkPath = Platform.environment['ANDROID_NDK_HOME'];
  print('ANDROID_NDK_HOME = $ndkPath');
  
  if (ndkPath != null) {
    final dir = Directory(ndkPath);
    print('Directory exists: ${dir.existsSync()}');
    
    final toolchain = File('$ndkPath/build/cmake/android.toolchain.cmake');
    print('Toolchain exists: ${toolchain.existsSync()}');
  }

  // Test 2: Glob check for ANDROID_HOME
  final androidHome = Platform.environment['ANDROID_HOME'];
  print('\nANDROID_HOME = $androidHome');
  if (androidHome != null) {
    final glob = Glob('ndk/*/');
    final entities = await glob.list(root: androidHome).toList();
    print('Glob matches for ndk/*/: ${entities.length}');
    for (final e in entities) {
      print('  ${e.path}');
    }
  }

  // Test 3: Direct path with trailing backslash issue
  final rawPath = r'E:\Android\Sdk\';
  print('\nRaw path: $rawPath');
  final glob2 = Glob('ndk/*/');
  final entities2 = await glob2.list(root: rawPath).toList();
  print('Glob matches: ${entities2.length}');
  for (final e in entities2) {
    print('  ${e.path}');
  }
}
