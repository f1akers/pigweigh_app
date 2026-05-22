import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

void main() async {
  // Simulate what native_toolchain_cmake does with ANDROID_HOME
  final androidHomeBackslash = r'E:\Android\Sdk';
  final pattern = '${androidHomeBackslash}/ndk/*/';
  print('Pattern with backslash ANDROID_HOME: $pattern');
  final glob1 = Glob(pattern);
  final results1 = await glob1.list().toList();
  print('  Matches: ${results1.length}');

  final androidHomeForward = 'E:/Android/Sdk';
  final pattern2 = '${androidHomeForward}/ndk/*/';
  print('\nPattern with forward slash ANDROID_HOME: $pattern2');
  final glob2 = Glob(pattern2);
  final results2 = await glob2.list().toList();
  print('  Matches: ${results2.length}');
}
