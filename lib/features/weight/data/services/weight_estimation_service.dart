import 'dart:io';
import 'dart:math' as math;

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
/// 2. Call [estimateFromImage] for the captured side-view photo.
/// 3. Call [calculateEstimate] after the side view is processed.
///
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

  /// Extract numeric weight from a label like "16 KG_Side" or "16 KG_Top".
  double _parseWeight(String label) {
    return double.parse(label.split(' ').first);
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
      final inputParams = inputTensor.params; // quantization scale + zeroPoint

      if (inputShape.length == 4) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
        _inputChannels = inputShape[3];
      }
      _isFloat32Input = inputType == TensorType.float32;

      final outputTensor = interpreter.getOutputTensor(0);
      final outputShape = outputTensor.shape; // e.g., [1, 95]
      final outputParams = outputTensor.params;
      if (outputShape.length >= 2) {
        _numClasses = outputShape[1];
      }

      interpreter.close();

      // ── CRITICAL DIAGNOSTIC ──────────────────────────────────────────────
      // inputType tells us what the model's input tensor actually expects.
      //   float32  → model may have internal preprocessing (Rescaling layer)
      //              OR expects a specific normalized float range.
      //   uint8    → quantized model; feed Uint8List [0, 255].
      //   int8     → quantized model; feed Int8List (centered at zeroPoint).
      //
      // inputParams.scale / zeroPoint (only meaningful for quantized tensors):
      //   If scale ≈ 0.00392 (≈1/255) and zp = 0 → uint8 model, input [0,255].
      //   If scale ≈ 0.00784 (≈2/255) and zp = -128 → int8, input [-128,127].
      //   If scale = 0 and zp = 0 → float32 with no quantization params.
      //
      // Run debug_model.py on the PC to test all normalizations definitively.
      AppLogger.debug(
        '═══ MODEL TENSOR METADATA ═══\n'
        '  input  : shape=$inputShape  type=$inputType  '
        'isFloat32=$_isFloat32Input\n'
        '  input  : quantScale=${inputParams.scale}  '
        'quantZeroPoint=${inputParams.zeroPoint}\n'
        '  output : shape=$outputShape  classes=$_numClasses\n'
        '  output : quantScale=${outputParams.scale}  '
        'quantZeroPoint=${outputParams.zeroPoint}\n'
        '═══════════════════════════════',
        tag: 'WEIGHT_DEBUG',
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

  /// Single-pass estimation — no augmentation.
  ///
  /// Runs one inference on the plain preprocessed image and returns the
  /// full probability distribution so the raw model output can be evaluated
  /// without any TTA interference.
  ///
  /// [onProgress] is kept for API compatibility but is only called once.
  Future<ViewEstimationResult> estimateFromImage({
    required String imagePath,
    required String viewType,
    void Function(int round, int count, String message)? onProgress,
    Duration roundDuration = const Duration(seconds: 10),
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'WeightEstimationService not initialized. Call initialize() first.',
      );
    }

    AppLogger.info(
      'Starting single-pass estimation on $viewType view: $imagePath',
      tag: 'WEIGHT',
    );

    onProgress?.call(1, 0, 'Running inference...');

    // ── Preprocess & infer ────────────────────────────────────────────────
    final tensor = await _preprocessImage(imagePath);

    final output = List.filled(_numClasses, 0.0).reshape([1, _numClasses]);
    _tfliteService.runInference(tensor, output);

    final rawOutput = (output[0] as List<dynamic>).cast<double>();

    final rawMax = rawOutput.reduce(math.max);
    final rawSum = rawOutput.reduce((a, b) => a + b);
    AppLogger.debug(
      'Raw model output — max: ${rawMax.toStringAsFixed(4)}, '
      'sum: ${rawSum.toStringAsFixed(4)} '
      '(${(rawSum - 1.0).abs() < 0.05 ? "✓ probabilities" : "⚠ unexpected — check model"})',
      tag: 'WEIGHT_DEBUG',
    );

    final probs = _ensureProbabilities(rawOutput);

    // ── Find winning class ────────────────────────────────────────────────
    int topIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[topIdx]) topIdx = i;
    }

    final winningWeight = _weights[topIdx];
    final winningConfidence = probs[topIdx];

    // ── Log all predictions ───────────────────────────────────────────────
    final predictions = _buildPredictions(probs);
    AppLogger.info(
      '✅ Result: ${winningWeight.toStringAsFixed(0)}kg '
      '(${(winningConfidence * 100).toStringAsFixed(1)}% confidence)',
      tag: 'WEIGHT',
    );
    for (final p in predictions.take(topN)) {
      AppLogger.debug(
        '  ${p.label}: ${(p.confidence * 100).toStringAsFixed(2)}%',
        tag: 'WEIGHT_DEBUG',
      );
    }

    onProgress?.call(1, 1, 'Done');

    return ViewEstimationResult(
      weightKg: winningWeight,
      confidence: winningConfidence,
      isAmbiguous: false,
      imagePath: imagePath,
      viewType: viewType,
      allPredictions: predictions.take(topN).toList(),
    );
  }

  /// Build the final weight estimate from the captured view results.
  ///
  /// Selects the view with the highest confidence. If confidences are equal,
  /// the top view is preferred. At least one of [topViewResult] or
  /// [sideViewResult] must be non-null.
  WeightEstimationModel calculateEstimate({
    ViewEstimationResult? topViewResult,
    ViewEstimationResult? sideViewResult,
  }) {
    assert(
      topViewResult != null || sideViewResult != null,
      'At least one view result must be provided.',
    );

    // Pick the view with higher confidence; ties favour the top view.
    final ViewEstimationResult selected;
    final String sourceView;

    if (topViewResult != null && sideViewResult != null) {
      if (sideViewResult.confidence > topViewResult.confidence) {
        selected = sideViewResult;
        sourceView = 'side';
      } else {
        selected = topViewResult;
        sourceView = 'top';
      }
    } else if (topViewResult != null) {
      selected = topViewResult;
      sourceView = 'top';
    } else {
      selected = sideViewResult!;
      sourceView = 'side';
    }

    AppLogger.info(
      'Selected $sourceView view: ${selected.weightKg}kg '
      '(${(selected.confidence * 100).toStringAsFixed(1)}%)',
      tag: 'WEIGHT',
    );

    return WeightEstimationModel(
      estimatedWeightKg: selected.weightKg,
      confidence: selected.confidence,
      sourceView: sourceView,
      imagePath: selected.imagePath,
      topViewResult: topViewResult,
      sideViewResult: sideViewResult,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Image Preprocessing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load an image from disk, resize to model dimensions, and
  /// return the input tensor as raw float32 [0–255].
  ///
  /// ## Why no external normalization?
  /// The YOLO classification TFLite export bakes ÷255 normalization
  /// INSIDE the TFLite graph as a preprocessing step. Applying
  /// normalization externally would double-normalize: every pixel
  /// collapses to near-zero, making the model produce near-uniform
  /// probabilities (~1% confidence on every class).
  ///
  /// Correct pipeline:
  ///   Raw JPEG → decode → EXIF-orient → resize → float32 [0–255] → model
  ///   (model internally: x/255 → YOLO classification layers → softmax)
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

    AppLogger.debug(
      'Image decoded — ${image.width}x${image.height} '
      'format: ${image.format} numChannels: ${image.numChannels}',
      tag: 'WEIGHT_DEBUG',
    );

    // Resize to model input dimensions.
    image = img.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );

    // ── Pixel-level sanity check (top-left 3×3 sample) ──────────────────────
    // Shows the raw channel values coming out of the image package.
    // Expected for a typical camera photo: values in [0–255].
    // If you see values in [0.0–1.0] the image package is using float32
    // format and you must multiply by 255 before building the tensor.
    final samplePixel = image.getPixel(0, 0);
    AppLogger.debug(
      'Sample pixel [0,0] → r:${samplePixel.r.toStringAsFixed(1)} '
      'g:${samplePixel.g.toStringAsFixed(1)} '
      'b:${samplePixel.b.toStringAsFixed(1)} '
      '(maxChannelValue: ${image.maxChannelValue})',
      tag: 'WEIGHT_DEBUG',
    );

    // Build the 4D input tensor [1, H, W, 3] as raw float32 [0–255].
    //
    // DO NOT normalize here. The YOLO model's baked-in preprocessing handles
    // ÷255 internally. Passing pre-normalized values means the model
    // applies the normalization a second time, collapsing all activations.
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputHeight,
        (y) => List.generate(_inputWidth, (x) {
          final pixel = image!.getPixel(x, y);
          // pixel.r/g/b are raw channel values [0–maxChannelValue].
          // For uint8 JPEG this is [0–255]; for float32 images it may be
          // [0.0–1.0] — the pixel sanity-check log above will reveal which.
          return [pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble()];
        }),
      ),
    );

    // ── Input-tensor statistics ──────────────────────────────────────────────
    // After the fix, expect: min ≈ 0, max ≈ 255, mean ≈ 100–180.
    // If you still see min/max in [0.0–1.0], the image is float32 format
    // → multiply pixel values by 255 inside the loop above.
    double tensorMin = double.infinity;
    double tensorMax = double.negativeInfinity;
    double tensorSum = 0;
    int tensorCount = 0;
    for (final batch in input) {
      for (final row in batch) {
        for (final col in row) {
          for (final v in col) {
            if (v < tensorMin) tensorMin = v;
            if (v > tensorMax) tensorMax = v;
            tensorSum += v;
            tensorCount++;
          }
        }
      }
    }
    AppLogger.debug(
      'Input tensor stats — '
      'min: ${tensorMin.toStringAsFixed(1)}, '
      'max: ${tensorMax.toStringAsFixed(1)}, '
      'mean: ${(tensorSum / tensorCount).toStringAsFixed(1)}',
      tag: 'WEIGHT_DEBUG',
    );

    return input;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Prediction Parsing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert raw logits to a probability distribution via softmax.
  ///
  /// Uses the numerically stable max-subtraction form:
  ///   softmax(x_i) = exp(x_i − max) / Σ exp(x_j − max)
  ///
  /// The YOLO model has softmax baked in, so this is only used as a
  /// safety-net fallback if the output unexpectedly doesn't sum to ≈ 1.0
  /// (e.g., a mismatched model was loaded by mistake).
  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / sumExp).toList();
  }

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

  // ═══════════════════════════════════════════════════════════════════════════
  // Test Time Augmentation (TTA) Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ensure the raw model output is a valid probability distribution.
  ///
  /// If the output already sums to ≈ 1.0, use it as-is.
  /// Otherwise apply softmax as a safety-net fallback.
  List<double> _ensureProbabilities(List<double> rawOutput) {
    final sum = rawOutput.reduce((a, b) => a + b);
    if ((sum - 1.0).abs() < 0.05) return rawOutput;
    return _softmax(rawOutput);
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
