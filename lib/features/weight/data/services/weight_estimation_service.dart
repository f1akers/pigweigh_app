import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:executorch_flutter/executorch_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../../services/ml/executorch_service.dart';
import '../models/weight_estimation_model.dart';

part 'weight_estimation_service.g.dart';

/// Service that handles ExecuTorch model inference for pig weight estimation.
///
/// **Lifecycle:**
/// 1. Call [initialize] once at app startup (loads labels).
/// 2. Call [estimateFromImage] for the captured side-view photo.
/// 3. Call [calculateEstimate] after the side view is processed.
///
class WeightEstimationService {
  WeightEstimationService({required ExecutorchService executorchService})
    : _executorchService = executorchService;

  final ExecutorchService _executorchService;

  /// Weight labels in model output order (index → label string).
  List<String> _labels = [];

  /// Parsed numeric weights corresponding to [_labels].
  List<double> _weights = [];

  /// Number of output classes.
  int _numClasses = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // Hard-coded model parameters
  // ═══════════════════════════════════════════════════════════════════════════
  /// The exported ExecuTorch model is a YOLOv8 detection model at 640×640
  /// with NCHW (channels-first) float32 input.
  static const int _inputHeight = 640;
  static const int _inputWidth = 640;
  static const int _inputChannels = 3;

  /// Confidence threshold for filtering YOLO detection anchors.
  static const double _detectionConfThreshold = 0.25;

  /// How many top predictions to retain in the result.
  static const int topN = 5;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ═══════════════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load labels from the asset file.
  ///
  /// Must be called once before any inference calls.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadLabels();
    _isInitialized = true;

    AppLogger.info(
      'WeightEstimationService initialized — '
      '${_labels.length} classes, '
      'input: $_inputHeight×$_inputWidth x$_inputChannels '
      'float32 (NCHW), mode: detection',
      tag: 'WEIGHT',
    );
  }

  /// Parse the labels file. Each line is a weight class (e.g., "16 KG_Side").
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
    final inputTensor = await _preprocessImage(imagePath);

    if (!_executorchService.isModelLoaded) {
      await _executorchService.loadModel();
    }

    final outputs = await _executorchService.forward([inputTensor]);
    final rawOutput = _parseDetectionOutput(outputs);

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

  /// Load an image from disk, letterbox-resize to 640×640, and return the
  /// input tensor as [TensorData] in NCHW float32 [0–255].
  ///
  /// ## Layout
  /// ExecuTorch (PyTorch) expects channels-first order:
  ///   [batch=1, channels=3, height=640, width=640]
  ///
  /// ## Normalization
  /// The YOLO model has internal preprocessing baked into the graph, so we
  /// pass raw pixel values in [0, 255] and do NOT divide by 255 externally.
  Future<TensorData> _preprocessImage(String imagePath) async {
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

    // Always letterbox for detection models.
    image = _letterboxResize(image);

    // ── Pixel-level sanity check (top-left sample) ──────────────────────
    final samplePixel = image.getPixel(0, 0);
    AppLogger.debug(
      'Sample pixel [0,0] → r:${samplePixel.r.toStringAsFixed(1)} '
      'g:${samplePixel.g.toStringAsFixed(1)} '
      'b:${samplePixel.b.toStringAsFixed(1)} '
      '(maxChannelValue: ${image.maxChannelValue})',
      tag: 'WEIGHT_DEBUG',
    );

    // Build flat NCHW float32 tensor [1, 3, 640, 640].
    final pixelCount = _inputHeight * _inputWidth;
    final floatData = Float32List(_inputChannels * pixelCount);

    for (var y = 0; y < _inputHeight; y++) {
      for (var x = 0; x < _inputWidth; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * _inputWidth + x;
        floatData[0 * pixelCount + idx] = pixel.r.toDouble();
        floatData[1 * pixelCount + idx] = pixel.g.toDouble();
        floatData[2 * pixelCount + idx] = pixel.b.toDouble();
      }
    }

    // ── Input-tensor statistics ──────────────────────────────────────────
    double tensorMin = double.infinity;
    double tensorMax = double.negativeInfinity;
    double tensorSum = 0;
    for (final v in floatData) {
      if (v < tensorMin) tensorMin = v;
      if (v > tensorMax) tensorMax = v;
      tensorSum += v;
    }
    AppLogger.debug(
      'Input tensor stats — '
      'min: ${tensorMin.toStringAsFixed(1)}, '
      'max: ${tensorMax.toStringAsFixed(1)}, '
      'mean: ${(tensorSum / floatData.length).toStringAsFixed(1)}',
      tag: 'WEIGHT_DEBUG',
    );

    return TensorData(
      shape: [1, _inputChannels, _inputHeight, _inputWidth],
      dataType: TensorType.float32,
      data: floatData.buffer.asUint8List(),
    );
  }

  /// Letterbox-resize for detection models: scale the image to fit within
  /// [_inputWidth]×[_inputHeight] while preserving aspect ratio, then pad
  /// with gray (114, 114, 114) to fill.
  ///
  /// YOLO detection models are trained on letterboxed images; stretching
  /// destroys detection accuracy.
  img.Image _letterboxResize(img.Image image) {
    final scale = math.min(
      _inputWidth / image.width,
      _inputHeight / image.height,
    );
    final newWidth = (image.width * scale).round();
    final newHeight = (image.height * scale).round();

    final resized = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    final letterboxed = img.Image(
      width: _inputWidth,
      height: _inputHeight,
      numChannels: resized.numChannels,
      format: resized.format,
    );
    img.fill(letterboxed, color: img.ColorRgb8(114, 114, 114));

    final pasteX = (_inputWidth - newWidth) ~/ 2;
    final pasteY = (_inputHeight - newHeight) ~/ 2;

    for (var y = 0; y < newHeight; y++) {
      for (var x = 0; x < newWidth; x++) {
        letterboxed.setPixel(pasteX + x, pasteY + y, resized.getPixel(x, y));
      }
    }

    AppLogger.debug(
      'Letterbox: ${image.width}x${image.height} → '
      '$newWidth' 'x$newHeight (scale ${scale.toStringAsFixed(4)}) '
      'pasted at ($pasteX, $pasteY) into ${_inputWidth}x$_inputHeight',
      tag: 'WEIGHT_DEBUG',
    );

    return letterboxed;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Prediction Parsing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse YOLOv8 raw detection output from ExecuTorch into a probability
  /// vector over [_numClasses].
  ///
  /// The model returns shape [1, numChannels, numAnchors] where:
  ///   numChannels = 4 bbox regression values + numClasses class logits
  ///   numAnchors  = 8400 (YOLOv8 default)
  ///
  /// For each anchor we:
  /// 1. Read class logits, apply sigmoid to get probabilities.
  /// 2. Find the max class probability for that anchor.
  /// 3. If it exceeds the threshold, update the per-class max confidence.
  ///
  /// Finally we softmax the per-class max confidences so downstream code
  /// receives a valid probability distribution.
  List<double> _parseDetectionOutput(List<TensorData> outputs) {
    if (outputs.isEmpty) {
      throw StateError('Model returned no outputs');
    }

    final outputTensor = outputs[0];
    final shape = outputTensor.shape;

    AppLogger.debug(
      'ExecuTorch output shape: $shape  dtype: ${outputTensor.dataType}',
      tag: 'WEIGHT_DEBUG',
    );

    if (shape.length != 3 || shape[0] != 1) {
      throw StateError(
        'Unexpected output shape: $shape. Expected [1, channels, anchors].',
      );
    }

    if (outputTensor.dataType != TensorType.float32) {
      throw StateError(
        'Unexpected output dtype: ${outputTensor.dataType}. Expected float32.',
      );
    }

    final numChannels = shape[1]!;
    final numAnchors = shape[2]!;
    final numClasses = numChannels - 4;

    if (numClasses != _numClasses) {
      AppLogger.warn(
        'Model class count ($numClasses) does not match label count ($_numClasses). '
        'Using min($_numClasses, $numClasses).',
        tag: 'WEIGHT',
      );
    }
    final effectiveClasses = math.min(_numClasses, numClasses);

    final flatOutput = outputTensor.data.buffer.asFloat32List();
    final perClassMaxConf = List<double>.filled(_numClasses, 0.0);

    for (var a = 0; a < numAnchors; a++) {
      // Channel-major layout: offset for [0, c, a] = c * numAnchors + a
      var maxClsProb = 0.0;
      var maxClsIdx = 0;

      for (var c = 0; c < numClasses; c++) {
        final offset = (4 + c) * numAnchors + a;
        final logit = flatOutput[offset];
        final prob = 1.0 / (1.0 + math.exp(-logit)); // sigmoid
        if (prob > maxClsProb) {
          maxClsProb = prob;
          maxClsIdx = c;
        }
      }

      if (maxClsProb > _detectionConfThreshold && maxClsIdx < effectiveClasses) {
        if (maxClsProb > perClassMaxConf[maxClsIdx]) {
          perClassMaxConf[maxClsIdx] = maxClsProb;
        }
      }
    }

    final hasDetections = perClassMaxConf.any((v) => v > 0);
    if (!hasDetections) {
      AppLogger.debug(
        'No detections above threshold $_detectionConfThreshold — '
        'returning uniform distribution',
        tag: 'WEIGHT_DEBUG',
      );
      return List<double>.filled(_numClasses, 1.0 / _numClasses);
    }

    return _softmax(perClassMaxConf);
  }

  /// Convert raw logits to a probability distribution via softmax.
  ///
  /// Uses the numerically stable max-subtraction form:
  ///   softmax(x_i) = exp(x_i − max) / Σ exp(x_j − max)
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
    executorchService: ref.watch(executorchServiceProvider),
  );
}
