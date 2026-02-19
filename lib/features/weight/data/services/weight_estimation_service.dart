import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../../services/ml/tflite_service.dart';
import '../models/weight_estimation_model.dart';

part 'weight_estimation_service.g.dart';

/// Service that handles TFLite model inference for pig weight estimation.
///
/// **Lifecycle:**
/// 1. Call [initialize] once at app startup (loads labels + inspects model).
/// 2. Call [estimateFromImage] for each captured photo (top or side view).
/// 3. Call [calculateBestEstimate] after both views are processed.
///
/// **Ambiguity detection:**
/// If two or more classes have confidence within [ambiguityThreshold] of the
/// top prediction, the result is flagged as ambiguous and the user should
/// retake that view.
class WeightEstimationService {
  WeightEstimationService({required TfliteService tfliteService})
    : _tfliteService = tfliteService;

  final TfliteService _tfliteService;

  /// Weight labels in model output order (index → label string).
  List<String> _labels = [];

  /// Parsed numeric weights corresponding to [_labels].
  List<double> _weights = [];

  /// Model input dimensions discovered at load time.
  int _inputHeight = 224;
  int _inputWidth = 224;
  int _inputChannels = 3;

  /// Whether the model expects float32 (normalized 0–1) or uint8 (0–255).
  bool _isFloat32Input = true;

  /// Number of output classes.
  int _numClasses = 0;

  /// If the gap between the top prediction and the runner-up is less than
  /// this threshold, the prediction is considered ambiguous.
  static const double ambiguityThreshold = 0.10;

  /// How many top predictions to retain in the result.
  static const int topN = 5;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ═══════════════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load labels from the asset file and inspect the model's tensor shapes.
  ///
  /// Must be called once before any inference calls.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadLabels();
    await _inspectModelShape();
    _isInitialized = true;

    AppLogger.info(
      'WeightEstimationService initialized — '
      '${_labels.length} classes, '
      'input: ${_inputHeight}x$_inputWidth x$_inputChannels '
      '(${_isFloat32Input ? "float32" : "uint8"})',
      tag: 'WEIGHT',
    );
  }

  /// Parse the labels file. Each line is a weight class (e.g., "85kg").
  /// Order must be preserved — line index matches model output index.
  Future<void> _loadLabels() async {
    final raw = await rootBundle.loadString(AppConstants.weightLabelsAsset);
    _labels = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    _weights = _labels.map(_parseWeight).toList();
    _numClasses = _labels.length;

    AppLogger.debug('Loaded $_numClasses weight labels', tag: 'WEIGHT');
  }

  /// Extract numeric weight from a label like "85kg".
  double _parseWeight(String label) {
    return double.parse(label.replaceAll('kg', ''));
  }

  /// Inspect the loaded model's input/output tensors to determine
  /// the expected image dimensions and data type.
  Future<void> _inspectModelShape() async {
    if (!_tfliteService.isModelLoaded) {
      await _tfliteService.loadModel();
    }

    // Access the interpreter to read tensor metadata.
    // TfliteService exposes the interpreter indirectly via runInference,
    // but we need shape info. We'll read from the model asset directly.
    try {
      final interpreter = await Interpreter.fromAsset(
        AppConstants.weightModelAsset,
      );

      final inputTensor = interpreter.getInputTensor(0);
      final inputShape = inputTensor.shape; // e.g., [1, 224, 224, 3]
      final inputType = inputTensor.type;

      if (inputShape.length == 4) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
        _inputChannels = inputShape[3];
      }
      _isFloat32Input = inputType == TensorType.float32;

      final outputTensor = interpreter.getOutputTensor(0);
      final outputShape = outputTensor.shape; // e.g., [1, 95]
      if (outputShape.length >= 2) {
        _numClasses = outputShape[1];
      }

      interpreter.close();

      AppLogger.debug(
        'Model shape — input: $inputShape ($inputType), '
        'output: $outputShape ($_numClasses classes)',
        tag: 'WEIGHT',
      );
    } catch (e) {
      AppLogger.warn(
        'Could not inspect model shape, using defaults: $e',
        tag: 'WEIGHT',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Inference
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run inference on a single image file.
  ///
  /// [imagePath] — absolute path to the image file on device.
  /// [viewType] — `'top'` or `'side'` (for labelling the result).
  ///
  /// Returns a [ViewEstimationResult] with the predicted weight,
  /// confidence, ambiguity flag, and top-N predictions.
  Future<ViewEstimationResult> estimateFromImage({
    required String imagePath,
    required String viewType,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'WeightEstimationService not initialized. Call initialize() first.',
      );
    }

    AppLogger.debug(
      'Running inference on $viewType view: $imagePath',
      tag: 'WEIGHT',
    );

    // 1. Load and preprocess the image.
    final input = await _preprocessImage(imagePath);

    // 2. Prepare output buffer.
    final output = List.filled(_numClasses, 0.0).reshape([1, _numClasses]);

    // 3. Run inference.
    _tfliteService.runInference(input, output);

    // 4. Parse output probabilities.
    final probabilities = (output[0] as List<dynamic>).cast<double>();

    // 5. Build sorted predictions.
    final predictions = _buildPredictions(probabilities);

    // 6. Check ambiguity.
    final isAmbiguous = _checkAmbiguity(predictions);

    final topPrediction = predictions.first;

    AppLogger.info(
      '$viewType view → ${topPrediction.label} '
      '(${(topPrediction.confidence * 100).toStringAsFixed(1)}%) '
      '${isAmbiguous ? "[AMBIGUOUS]" : ""}',
      tag: 'WEIGHT',
    );

    return ViewEstimationResult(
      weightKg: topPrediction.weightKg,
      confidence: topPrediction.confidence,
      isAmbiguous: isAmbiguous,
      imagePath: imagePath,
      viewType: viewType,
      allPredictions: predictions.take(topN).toList(),
    );
  }

  /// Compare both views and pick the one with higher confidence.
  ///
  /// Returns a [WeightEstimationModel] with the final estimate.
  /// Call this after both views have been processed individually.
  WeightEstimationModel calculateBestEstimate({
    required ViewEstimationResult topViewResult,
    required ViewEstimationResult sideViewResult,
  }) {
    final bestIsTop = topViewResult.confidence >= sideViewResult.confidence;

    final winner = bestIsTop ? topViewResult : sideViewResult;

    AppLogger.info(
      'Best estimate: ${winner.weightKg}kg from ${winner.viewType} view '
      '(${(winner.confidence * 100).toStringAsFixed(1)}%)',
      tag: 'WEIGHT',
    );

    return WeightEstimationModel(
      estimatedWeightKg: winner.weightKg,
      confidence: winner.confidence,
      sourceView: winner.viewType,
      imagePath: winner.imagePath,
      topViewResult: topViewResult,
      sideViewResult: sideViewResult,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Image Preprocessing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load an image from disk, resize to model dimensions, normalise,
  /// and return the input tensor.
  Future<List<List<List<List<double>>>>> _preprocessImage(
    String imagePath,
  ) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);

    if (image == null) {
      throw ArgumentError('Could not decode image at $imagePath');
    }

    // Handle EXIF orientation.
    image = img.bakeOrientation(image);

    // Resize to model input dimensions.
    image = img.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );

    // Build the 4D input tensor [1, height, width, channels].
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputHeight,
        (y) => List.generate(_inputWidth, (x) {
          final pixel = image!.getPixel(x, y);

          if (_isFloat32Input) {
            // Normalize to 0.0 – 1.0
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          } else {
            return [pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble()];
          }
        }),
      ),
    );

    return input;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Prediction Parsing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build a sorted list of [PredictionClass] from raw output probabilities.
  List<PredictionClass> _buildPredictions(List<double> probabilities) {
    final predictions = <PredictionClass>[];

    for (var i = 0; i < probabilities.length && i < _numClasses; i++) {
      predictions.add(
        PredictionClass(
          weightKg: _weights[i],
          confidence: probabilities[i],
          label: _labels[i],
        ),
      );
    }

    // Sort descending by confidence.
    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return predictions;
  }

  /// Check if the prediction is ambiguous — two or more top classes
  /// have confidence within [ambiguityThreshold] of each other.
  bool _checkAmbiguity(List<PredictionClass> sortedPredictions) {
    if (sortedPredictions.length < 2) return false;

    final top = sortedPredictions[0].confidence;
    final runnerUp = sortedPredictions[1].confidence;

    // If the difference between #1 and #2 is less than the threshold,
    // the model is uncertain → ambiguous.
    return (top - runnerUp) < ambiguityThreshold;
  }
}

/// Singleton provider for [WeightEstimationService].
///
/// Initialisation must happen before first use. The [weightFormProvider]
/// handles calling [initialize] during its build phase.
@Riverpod(keepAlive: true)
WeightEstimationService weightEstimationService(Ref ref) {
  return WeightEstimationService(
    tfliteService: ref.watch(tfliteServiceProvider),
  );
}
