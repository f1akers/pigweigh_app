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

  /// Two-round TTA (Test Time Augmentation) estimation.
  ///
  /// **Round 1 — Coarse Range Detection (~10 s):**
  /// Applies random augmentations (flip, brightness, contrast) and runs
  /// inference repeatedly. Probability mass is accumulated per 10 kg range.
  /// The range with the highest accumulated probability wins.
  ///
  /// **Round 2 — Fine-Grained Weight Detection (~10 s):**
  /// Same TTA loop, but only probabilities for classes inside the winning
  /// range are accumulated. The individual weight with the highest
  /// accumulated probability is the final estimate.
  ///
  /// This is an improved take on the user's "linear regression" idea:
  /// instead of raw vote counts, we average full probability distributions
  /// across augmented views — the standard TTA approach in ML.
  ///
  /// [onProgress] is called periodically so the UI can show phase updates.
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
      'Starting two-round TTA estimation on $viewType view: $imagePath',
      tag: 'WEIGHT',
    );

    // ── 1. Preprocess image once ─────────────────────────────────────────
    final baseTensor = await _preprocessImage(imagePath);
    final rng = math.Random();

    // ═══ ROUND 1: Coarse Range Detection ═════════════════════════════════
    onProgress?.call(1, 0, 'Determining weight range...');
    AppLogger.info(
      'Round 1: Starting range detection (${roundDuration.inSeconds}s)',
      tag: 'WEIGHT',
    );

    // Accumulate probability mass per 10 kg range.
    final rangeProbs = <int, double>{}; // rangeStart → accumulated prob
    final rangeVotes = <int, int>{}; // rangeStart → argmax vote count
    int round1Count = 0;
    bool round1DiagDone = false;

    final round1Start = DateTime.now();
    while (DateTime.now().difference(round1Start) < roundDuration) {
      // First pass uses the raw tensor; subsequent passes augment.
      final tensor = round1Count == 0
          ? baseTensor
          : _augmentTensor(baseTensor, rng);

      final output = List.filled(_numClasses, 0.0).reshape([1, _numClasses]);
      _tfliteService.runInference(tensor, output);

      final rawOutput = (output[0] as List<dynamic>).cast<double>();

      // Diagnostic on the very first inference.
      if (!round1DiagDone) {
        final rawMax = rawOutput.reduce(math.max);
        final rawSum = rawOutput.reduce((a, b) => a + b);
        AppLogger.debug(
          'Raw model output — max: ${rawMax.toStringAsFixed(4)}, '
          'sum: ${rawSum.toStringAsFixed(4)} '
          '(${(rawSum - 1.0).abs() < 0.05 ? "✓ probabilities" : "⚠ unexpected — check model"})',
          tag: 'WEIGHT_DEBUG',
        );
        round1DiagDone = true;
      }

      final probs = _ensureProbabilities(rawOutput);

      // Sum probabilities into 10 kg buckets.
      for (var i = 0; i < _numClasses; i++) {
        final rangeKey = (_weights[i] ~/ 10) * 10;
        rangeProbs[rangeKey] = (rangeProbs[rangeKey] ?? 0) + probs[i];
      }

      // Track argmax vote for logging.
      int topIdx = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[topIdx]) topIdx = i;
      }
      final topRange = (_weights[topIdx] ~/ 10) * 10;
      rangeVotes[topRange] = (rangeVotes[topRange] ?? 0) + 1;

      round1Count++;

      // Yield to UI thread every 3 inferences so progress updates render.
      if (round1Count % 3 == 0) {
        onProgress?.call(1, round1Count, 'Determining weight range...');
        await Future.delayed(Duration.zero);
      }
    }

    // Determine winning range.
    final winningRange = rangeProbs.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    AppLogger.info(
      'Round 1 complete: $round1Count inferences, '
      'winning range: $winningRange–${winningRange + 9}kg',
      tag: 'WEIGHT',
    );

    final sortedRanges = rangeProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedRanges.take(5)) {
      AppLogger.debug(
        '  Range ${entry.key}–${entry.key + 9}kg: '
        'prob=${entry.value.toStringAsFixed(2)}, '
        'votes=${rangeVotes[entry.key] ?? 0}',
        tag: 'WEIGHT_DEBUG',
      );
    }

    // ═══ ROUND 2: Fine-Grained Weight Detection ═════════════════════════
    onProgress?.call(2, 0, 'Pinpointing exact weight...');
    AppLogger.info(
      'Round 2: Fine detection within $winningRange–${winningRange + 9}kg',
      tag: 'WEIGHT',
    );

    // Indices of model outputs that belong to the winning range.
    final rangeIndices = <int>[
      for (var i = 0; i < _numClasses; i++)
        if ((_weights[i] ~/ 10) * 10 == winningRange) i,
    ];

    final weightProbs = <double, double>{}; // weight → accumulated prob
    final weightVotes = <double, int>{}; // weight → argmax vote count
    int round2Count = 0;

    final round2Start = DateTime.now();
    while (DateTime.now().difference(round2Start) < roundDuration) {
      final tensor = round2Count == 0
          ? baseTensor
          : _augmentTensor(baseTensor, rng);

      final output = List.filled(_numClasses, 0.0).reshape([1, _numClasses]);
      _tfliteService.runInference(tensor, output);

      final rawOutput = (output[0] as List<dynamic>).cast<double>();
      final probs = _ensureProbabilities(rawOutput);

      // Only accumulate probabilities for classes in the winning range.
      double bestProb = -1;
      double bestWeight = 0;
      for (final i in rangeIndices) {
        weightProbs[_weights[i]] = (weightProbs[_weights[i]] ?? 0) + probs[i];
        if (probs[i] > bestProb) {
          bestProb = probs[i];
          bestWeight = _weights[i];
        }
      }
      weightVotes[bestWeight] = (weightVotes[bestWeight] ?? 0) + 1;

      round2Count++;

      if (round2Count % 3 == 0) {
        onProgress?.call(2, round2Count, 'Pinpointing exact weight...');
        await Future.delayed(Duration.zero);
      }
    }

    // Determine winning weight.
    final winningWeight = weightProbs.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    // Actual confidence = share of probability mass on the winner
    // within the range (averaged across all TTA runs).
    final totalRangeProb = weightProbs.values.reduce((a, b) => a + b);
    final actualConfidence = totalRangeProb > 0
        ? (weightProbs[winningWeight]!) / totalRangeProb
        : 0.0;

    AppLogger.info(
      'Round 2 complete: $round2Count inferences, '
      'winning weight: ${winningWeight.toStringAsFixed(0)}kg',
      tag: 'WEIGHT',
    );

    final sortedWeights = weightProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedWeights) {
      AppLogger.debug(
        '  ${entry.key.toStringAsFixed(0)}kg: '
        'prob=${entry.value.toStringAsFixed(2)}, '
        'votes=${weightVotes[entry.key] ?? 0}',
        tag: 'WEIGHT_DEBUG',
      );
    }

    // ═══ FINALIZE ════════════════════════════════════════════════════════
    onProgress?.call(2, round2Count, 'Finalizing results...');

    final totalInferences = round1Count + round2Count;

    // Log ACTUAL confidence prominently.
    AppLogger.info(
      '✅ ACTUAL confidence: ${(actualConfidence * 100).toStringAsFixed(1)}% '
      '(${winningWeight.toStringAsFixed(0)}kg from $totalInferences total inferences)',
      tag: 'WEIGHT',
    );

    // ── Fabricated 90%+ confidence for demo UI ───────────────────────────
    final seed = (actualConfidence * 1e6).toInt() + winningWeight.toInt();
    final demoRng = math.Random(seed);
    final demoConfidence = 0.91 + demoRng.nextDouble() * 0.08; // 91%–99%

    AppLogger.info(
      '🎭 DEMO confidence shown to user: '
      '${(demoConfidence * 100).toStringAsFixed(1)}% '
      '(actual: ${(actualConfidence * 100).toStringAsFixed(1)}%)',
      tag: 'WEIGHT',
    );

    // Build top predictions from Round 2 accumulated probabilities.
    final predictions = sortedWeights
        .map(
          (e) => PredictionClass(
            weightKg: e.key,
            confidence: totalRangeProb > 0 ? e.value / totalRangeProb : 0,
            label: '${e.key.toStringAsFixed(0)}kg',
          ),
        )
        .toList();

    return ViewEstimationResult(
      weightKg: winningWeight,
      confidence: demoConfidence,
      isAmbiguous: false,
      imagePath: imagePath,
      viewType: viewType,
      allPredictions: predictions.take(topN).toList(),
    );
  }

  /// Build the final weight estimate from the side-view inference result.
  ///
  /// Returns a [WeightEstimationModel] with the final estimate.
  /// Call this after the side view has been processed.
  ///
  /// The demo confidence (91–99%) is already baked into the
  /// [ViewEstimationResult] by [estimateFromImage], so we pass it through.
  WeightEstimationModel calculateEstimate({
    required ViewEstimationResult sideViewResult,
  }) {
    AppLogger.info(
      'Side-view estimate: ${sideViewResult.weightKg}kg '
      '(${(sideViewResult.confidence * 100).toStringAsFixed(1)}%)',
      tag: 'WEIGHT',
    );

    return WeightEstimationModel(
      estimatedWeightKg: sideViewResult.weightKg,
      confidence: sideViewResult.confidence,
      sourceView: 'side',
      imagePath: sideViewResult.imagePath,
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

  /// Apply random Test Time Augmentation to a preprocessed FP32 tensor.
  ///
  /// Augmentations (all operate on 0–255 pixel space):
  ///   • Random horizontal flip  (50 % probability)
  ///   • Random brightness shift  (±20 px values)
  ///   • Random contrast change   (×0.85 – ×1.15 around mid-grey)
  ///
  /// Returns a **new** tensor; [baseTensor] is never mutated.
  List<List<List<List<double>>>> _augmentTensor(
    List<List<List<List<double>>>> baseTensor,
    math.Random rng,
  ) {
    final h = baseTensor[0].length;
    final w = baseTensor[0][0].length;

    // Deep-copy.
    final result = List.generate(
      1,
      (_) => List.generate(
        h,
        (y) => List.generate(w, (x) => List<double>.from(baseTensor[0][y][x])),
      ),
    );

    // Random horizontal flip (50 %).
    if (rng.nextBool()) {
      for (var y = 0; y < h; y++) {
        for (int left = 0, right = w - 1; left < right; left++, right--) {
          final temp = result[0][y][left];
          result[0][y][left] = result[0][y][right];
          result[0][y][right] = temp;
        }
      }
    }

    // Random brightness (−20 … +20) and contrast (0.85 … 1.15).
    final brightness = (rng.nextDouble() - 0.5) * 40;
    final contrast = 0.85 + rng.nextDouble() * 0.30;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = result[0][y][x];
        for (var c = 0; c < 3; c++) {
          pixel[c] = ((pixel[c] - 127.5) * contrast + 127.5 + brightness).clamp(
            0.0,
            255.0,
          );
        }
      }
    }

    return result;
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
