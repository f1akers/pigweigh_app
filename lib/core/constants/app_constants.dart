/// Application-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'PigWeigh';

  /// TFLite model asset path.
  static const String weightModelAsset =
      'assets/models/pig_weight_estimation.tflite';

  /// Weight class labels asset path.
  static const String weightLabelsAsset = 'assets/labels/pig_weight_labels.txt';
}
