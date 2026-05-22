import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

void main() async {
  // Test with trailing backslash (current ANDROID_HOME value)
  final pathWithSlash = r'E:\Android\Sdk\ndk\*\';
  print('Testing: $pathWithSlash');
  try {
    final glob1 = Glob(pathWithSlash);
    final results1 = await glob1.list().toList();
    print('  Matches: ${results1.length}');
  } catch (e) {
    print('  Error: $e');
  }

  // Test with combined pattern (how native_toolchain_c does it)
  final androidHome = r'E:\Android\Sdk\';
  final pattern = 'ndk/*/';
  final combined = androidHome + pattern;
  print('\nTesting combined: $combined');
  try {
    final glob2 = Glob(combined);
    final results2 = await glob2.list().toList();
    print('  Matches: ${results2.length}');
  } catch (e) {
    print('  Error: $e');
  }

  // Test without trailing backslash
  final androidHome2 = r'E:\Android\Sdk';
  final combined2 = androidHome2 + r'\' + pattern;
  print('\nTesting combined2: $combined2');
  try {
    final glob3 = Glob(combined2);
    final results3 = await glob3.list().toList();
    print('  Matches: ${results3.length}');
  } catch (e) {
    print('  Error: $e');
  }

  // Test with forward slash combination
  final combined3 = 'E:/Android/Sdk/ndk/*/';
  print('\nTesting forward slashes: $combined3');
  try {
    final glob4 = Glob(combined3);
    final results4 = await glob4.list().toList();
    print('  Matches: ${results4.length}');
  } catch (e) {
    print('  Error: $e');
  }
}
