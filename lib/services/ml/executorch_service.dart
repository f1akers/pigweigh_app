import 'package:executorch_flutter/executorch_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

part 'executorch_service.g.dart';

/// Service for loading and running ExecuTorch model inference.
///
/// Usage:
/// ```dart
/// final service = ref.read(executorchServiceProvider);
/// await service.loadModel();
/// final outputs = await service.forward([inputTensor]);
/// ```
class ExecutorchService {
  ExecuTorchModel? _model;

  bool get isModelLoaded => _model != null;

  /// Load the ExecuTorch model from assets.
  Future<void> loadModel() async {
    try {
      _model = await ExecuTorchModel.loadFromAsset(
        AppConstants.weightModelAsset,
      );
      AppLogger.info('ExecuTorch model loaded successfully', tag: 'ML');
    } catch (e) {
      AppLogger.error('Failed to load ExecuTorch model', tag: 'ML', error: e);
      rethrow;
    }
  }

  /// Run inference on the loaded model.
  ///
  /// [inputs] must match the model's expected input tensors.
  /// Returns a list of output [TensorData] values.
  Future<List<TensorData>> forward(List<TensorData> inputs) async {
    if (_model == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }
    return _model!.forward(inputs);
  }

  Future<void> dispose() async {
    await _model?.dispose();
    _model = null;
    AppLogger.info('ExecuTorch model disposed', tag: 'ML');
  }
}

/// Singleton provider for [ExecutorchService].
@Riverpod(keepAlive: true)
ExecutorchService executorchService(Ref ref) {
  final service = ExecutorchService();
  ref.onDispose(() => service.dispose());
  return service;
}
