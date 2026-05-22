import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

void main() async {
  // Simulate what native_toolchain_c does with ANDROID_HOME
  final androidHomeBackslash = r'E:\Android\Sdk\';
  final pattern = 'ndk/*/';
  final combinedBackslash = androidHomeBackslash + pattern;
  
  print('With backslash ANDROID_HOME:');
  print('  Combined path: $combinedBackslash');
  final glob1 = Glob(combinedBackslash);
  final results1 = await glob1.list().toList();
  print('  Matches: ${results1.length}');

  final androidHomeForward = 'E:/Android/Sdk/';
  final combinedForward = androidHomeForward + pattern;
  
  print('\nWith forward slash ANDROID_HOME:');
  print('  Combined path: $combinedForward');
  final glob2 = Glob(combinedForward);
  final results2 = await glob2.list().toList();
  print('  Matches: ${results2.length}');
}
