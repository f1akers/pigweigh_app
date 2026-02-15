import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

part 'tflite_service.g.dart';

/// Service for loading and running TFLite model inference.
///
/// Usage:
/// ```dart
/// final service = ref.read(tfliteServiceProvider);
/// await service.loadModel();
/// final output = service.runInference(inputData);
/// ```
class TfliteService {
  Interpreter? _interpreter;

  bool get isModelLoaded => _interpreter != null;

  /// Load the TFLite model from assets.
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(AppConstants.weightModelAsset);
      AppLogger.info('TFLite model loaded successfully', tag: 'ML');
    } catch (e) {
      AppLogger.error('Failed to load TFLite model', tag: 'ML', error: e);
      rethrow;
    }
  }

  /// Run inference on the loaded model.
  ///
  /// [input] and [output] shapes must match the model's expected I/O tensors.
  /// Consult your model documentation for the exact shapes.
  void runInference(Object input, Object output) {
    if (_interpreter == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }
    _interpreter!.run(input, output);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    AppLogger.info('TFLite interpreter disposed', tag: 'ML');
  }
}

/// Singleton provider for [TfliteService].
@Riverpod(keepAlive: true)
TfliteService tfliteService(Ref ref) {
  final service = TfliteService();
  ref.onDispose(() => service.dispose());
  return service;
}
