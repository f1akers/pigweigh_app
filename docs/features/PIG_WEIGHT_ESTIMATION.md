# Feature: Pig Weight Estimation (Flutter — User)

> **Purpose**: Allows users to capture top-view and side-view photos of a pig, run on-device TFLite inference to estimate weight in kilograms, and display the estimated price based on the current SRP.

---

## 1. Overview

This is the **core user-facing feature** of PigWeigh. Users take two photos of a pig — one from the top and one from the side. The TFLite model processes each photo independently and classifies the pig's weight into one of 95 weight classes (ranging from 31kg to 192kg). The photo with the higher confidence score is selected as the final estimate.

The result screen shows the estimated weight, estimated market value (weight × current SRP per kg), and the current SRP for reference. Users can navigate to the price history from this screen.

**This feature is fully offline** — the TFLite model runs on-device, and the SRP is read from the Drift cache.

### Why It Exists

- Pig farmers need a quick, non-invasive way to estimate pig weight without a physical scale.
- Knowing the estimated market value helps farmers decide when to sell.
- On-device inference means the feature works anywhere, even without internet.

---

## 2. Dependencies

| Depends On                            | Why                                   |
| ------------------------------------- | ------------------------------------- |
| `TfliteService`                       | Run on-device ML model inference      |
| `camera` package                      | Capture photos from device camera     |
| `image_picker` package                | Alternative image input (gallery)     |
| [SRP_MANAGEMENT](SRP_MANAGEMENT.md)   | Read active SRP for price calculation |
| `Drift` (AppDatabase)                 | Read cached active SRP when offline   |
| Asset: `pig_weight_estimation.tflite` | The classification model              |
| Asset: `pig_weight_labels.txt`        | Weight class labels (95 classes)      |

---

## 3. Data Layer

### 3.1 TFLite Model Specification

| Property        | Value                                                                     |
| --------------- | ------------------------------------------------------------------------- |
| **Model file**  | `assets/models/pig_weight_estimation.tflite`                              |
| **Labels file** | `assets/labels/pig_weight_labels.txt`                                     |
| **Task**        | Image classification                                                      |
| **Input**       | Preprocessed image tensor (shape depends on model — inspect at load time) |
| **Output**      | Probability distribution over 95 weight classes                           |
| **Classes**     | 95 weight labels from 31kg to 192kg (see below)                           |

### 3.2 Weight Labels

The model's output classes, sorted numerically:

```
31kg, 33kg, 38kg, 39kg, 40kg, 44kg, 45kg, 46kg, 47kg, 48kg,
50kg, 52kg, 53kg, 56kg, 57kg, 58kg, 59kg, 60kg, 62kg, 64kg,
65kg, 66kg, 67kg, 68kg, 69kg, 70kg, 72kg, 73kg, 74kg, 79kg,
81kg, 82kg, 83kg, 84kg, 85kg, 86kg, 87kg, 88kg, 89kg, 90kg,
92kg, 94kg, 95kg, 96kg, 98kg, 99kg, 100kg, 101kg, 102kg, 104kg,
106kg, 107kg, 108kg, 109kg, 112kg, 113kg, 114kg, 117kg, 119kg, 120kg,
122kg, 123kg, 124kg, 125kg, 126kg, 127kg, 128kg, 129kg, 130kg, 131kg,
132kg, 133kg, 137kg, 141kg, 145kg, 146kg, 147kg, 148kg, 149kg, 153kg,
155kg, 156kg, 157kg, 158kg, 160kg, 165kg, 168kg, 175kg, 178kg, 180kg,
181kg, 182kg, 183kg, 186kg, 192kg
```

> **Note**: The labels file lists classes in the order the model outputs them (file line order). The label parsing must preserve this order to correctly map output indices to weight values.

### 3.3 Data Models

```dart
// lib/features/weight/data/models/weight_estimation_model.dart

@freezed
abstract class WeightEstimationModel with _$WeightEstimationModel {
  const factory WeightEstimationModel({
    required double estimatedWeightKg,   // e.g., 85.0
    required double confidence,           // 0.0 – 1.0, from the winning class
    required String sourceView,           // 'top' or 'side'
    required String imagePath,            // Path to the selected photo
    WeightEstimationDetail? topViewResult,
    WeightEstimationDetail? sideViewResult,
  }) = _WeightEstimationModel;
}

@freezed
abstract class WeightEstimationDetail with _$WeightEstimationDetail {
  const factory WeightEstimationDetail({
    required double weightKg,
    required double confidence,
    required String imagePath,
  }) = _WeightEstimationDetail;
}

// lib/features/weight/data/models/price_estimation_model.dart

@freezed
abstract class PriceEstimationModel with _$PriceEstimationModel {
  const factory PriceEstimationModel({
    required double estimatedWeightKg,
    required double srpPerKg,              // Current SRP price
    required double estimatedTotalPrice,   // weight × SRP
    required bool isSrpCached,             // true if SRP came from offline cache
    DateTime? srpEffectiveDate,            // startDate of the SRP used
  }) = _PriceEstimationModel;
}
```

### 3.4 Weight Estimation Service

```dart
// lib/features/weight/data/services/weight_estimation_service.dart

class WeightEstimationService {
  WeightEstimationService({
    required TfliteService tfliteService,
  });

  List<String> _labels = [];

  /// Load weight labels from the asset file.
  /// Must be called once before inference.
  Future<void> loadLabels() async {
    final raw = await rootBundle.loadString('assets/labels/pig_weight_labels.txt');
    _labels = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Parse a label string (e.g., "85kg") into a numeric weight.
  double _parseWeight(String label) {
    return double.parse(label.replaceAll('kg', ''));
  }

  /// Run inference on a single image.
  /// Returns the predicted weight class and confidence.
  Future<WeightEstimationDetail> estimateFromImage(String imagePath) async {
    // 1. Load and preprocess the image to match model input tensor shape
    // 2. Run tfliteService.runInference(input, output)
    // 3. Find the index with highest probability in output
    // 4. Map index to label: _labels[maxIndex]
    // 5. Parse weight from label
    // 6. Return WeightEstimationDetail(weightKg, confidence, imagePath)
  }

  /// Run inference on both top and side view photos.
  /// Returns the result from the photo with higher confidence.
  Future<WeightEstimationModel> estimateWeight({
    required String topViewPath,
    required String sideViewPath,
  }) async {
    final topResult = await estimateFromImage(topViewPath);
    final sideResult = await estimateFromImage(sideViewPath);

    // Pick the result with higher confidence
    final bestIsTop = topResult.confidence >= sideResult.confidence;

    return WeightEstimationModel(
      estimatedWeightKg: bestIsTop ? topResult.weightKg : sideResult.weightKg,
      confidence: bestIsTop ? topResult.confidence : sideResult.confidence,
      sourceView: bestIsTop ? 'top' : 'side',
      imagePath: bestIsTop ? topResult.imagePath : sideResult.imagePath,
      topViewResult: topResult,
      sideViewResult: sideResult,
    );
  }
}
```

### 3.5 Price Estimation Logic

```dart
// lib/features/weight/data/services/price_estimation_service.dart

class PriceEstimationService {
  PriceEstimationService({required SrpRepository srpRepository});

  /// Calculate estimated price from weight and current SRP.
  Future<PriceEstimationModel> calculatePrice(double weightKg) async {
    // 1. Get active SRP (from cache if offline)
    // 2. Multiply: totalPrice = weightKg × srpPerKg
    // 3. Return PriceEstimationModel with all details
  }
}
```

### 3.6 Providers

| Provider                          | Type                 | Purpose                                                  |
| --------------------------------- | -------------------- | -------------------------------------------------------- |
| `weightEstimationServiceProvider` | Provider (keepAlive) | Singleton `WeightEstimationService`                      |
| `priceEstimationServiceProvider`  | Provider (keepAlive) | Singleton `PriceEstimationService`                       |
| `weightFormProvider`              | AsyncNotifier        | Manages photo capture state + inference flow             |
| `weightResultProvider`            | StateProvider        | Holds the latest estimation result for the result screen |

```dart
// lib/features/weight/data/providers/weight_providers.dart

@Riverpod(keepAlive: true)
WeightEstimationService weightEstimationService(Ref ref) {
  return WeightEstimationService(
    tfliteService: ref.watch(tfliteServiceProvider),
  );
}

@Riverpod(keepAlive: true)
PriceEstimationService priceEstimationService(Ref ref) {
  return PriceEstimationService(
    srpRepository: ref.watch(srpRepositoryProvider),
  );
}
```

### 3.7 Image Preprocessing Notes

The exact preprocessing pipeline depends on the TFLite model's input tensor shape. At model load time, inspect the interpreter's input tensor:

```dart
final inputTensor = interpreter.getInputTensor(0);
final inputShape = inputTensor.shape;  // e.g., [1, 224, 224, 3]
final inputType = inputTensor.type;    // e.g., uint8 or float32
```

Common preprocessing steps:

1. Decode image to bitmap
2. Resize to model's expected dimensions (e.g., 224×224)
3. Normalize pixel values (0–255 → 0.0–1.0 for float32, or keep as uint8)
4. Reshape to match input tensor (e.g., `[1, 224, 224, 3]` for batch of 1, HxW, RGB)

> **Implementation note**: The exact preprocessing will be determined when the model's input tensor shape is inspected at runtime. Document the discovered shape here after first load.

---

## 4. Presentation Layer

> **Note**: Presentation layer (screens, widgets, design) will be documented and implemented separately when design screenshots are provided.

### 4.1 Screens (Planned)

| Screen               | Route            | Auth   | Description                                              |
| -------------------- | ---------------- | ------ | -------------------------------------------------------- |
| `WeightFormScreen`   | `/weight`        | Public | Two photo inputs (top view + side view), estimate button |
| `WeightResultScreen` | `/weight/result` | Public | Shows estimated weight, estimated price, SRP reference   |

### 4.2 Flow

```
User opens app
      │
      ▼
WeightFormScreen
  ├─ Capture/select TOP VIEW photo
  ├─ Capture/select SIDE VIEW photo
  └─ Tap "Estimate Weight"
      │
      ▼
Processing (loading indicator)
  ├─ Run TFLite on top view → get weight + confidence
  ├─ Run TFLite on side view → get weight + confidence
  └─ Pick the result with higher confidence
      │
      ▼
WeightResultScreen
  ├─ Estimated weight: {X} kg
  ├─ Estimated price: ₱{weight × SRP}
  ├─ Market SRP: ₱{SRP}/kg (effective since {date})
  ├─ [Button] "View Price History" → navigates to PriceHistoryScreen
  └─ [Button] "Estimate Again" → back to WeightFormScreen
```

### 4.3 Widgets (Planned)

| Widget                | Description                                                     |
| --------------------- | --------------------------------------------------------------- |
| `PhotoCaptureCard`    | Camera/gallery input card for a single photo (top or side view) |
| `WeightResultCard`    | Displays estimated weight prominently                           |
| `PriceEstimationCard` | Shows estimated price calculation breakdown                     |
| `SrpReferenceCard`    | Shows current SRP with effective date                           |

### 4.4 UI Behaviors (Placeholder)

**Weight Form Screen:**

- Two large photo input areas labeled "Top View" and "Side View"
- Each area: tap to open camera or choose from gallery
- Photo preview after capture
- "Estimate Weight" button (disabled until both photos are captured)
- Loading/processing indicator during inference

**Weight Result Screen:**

- Large display of estimated weight (e.g., `85 kg`)
- Confidence indicator (which view was used)
- Estimated market value: `₱{price}` (weight × SRP/kg)
- Current SRP reference: `₱{SRP}/kg · Effective since {date}`
- Button: "View Price History" → navigates to `/price-history`
- Button: "Estimate Again" → returns to form (clears state)
- If SRP is from cache, show "Offline price — last updated {date}"

### 4.5 Navigation / Routing

```dart
// AppRoutes additions:
static const String weightForm = '/weight';
static const String weightResult = '/weight/result';

// No auth required — public feature
// weightResult expects the estimation data to be available via provider
```

---

## 5. Offline Behavior

This feature is **100% offline-capable**:

| Component              | Offline Source              |
| ---------------------- | --------------------------- |
| TFLite model           | Bundled in `assets/models/` |
| Weight labels          | Bundled in `assets/labels/` |
| Camera capture         | Device hardware             |
| Active SRP (for price) | Drift cache                 |
| Price history link     | Drift cache                 |

The only scenario where price estimation is unavailable is if the Drift cache has **never** been populated (fresh install with no prior connectivity). In that case, show the weight estimate without the price, and display "Connect to the internet to load current market prices."

---

## 6. Business Rules

1. **Both photos required** — the estimate button is disabled until both top and side views are captured.
2. **Higher confidence wins** — the model runs on both photos independently; the result with the higher confidence score is displayed.
3. **Weight classes are discrete** — the model outputs one of 95 specific weight values (not a continuous range). Display the exact class label (e.g., `85 kg`, not `84.7 kg`).
4. **Price = weight × SRP per kg** — simple multiplication. Display with 2 decimal places and ₱ symbol.
5. **No data sent to server** — photos and estimation results stay on-device. This is purely local computation.
6. **Model must be loaded once** — `TfliteService.loadModel()` should be called during app initialization (in `main.dart` or via a provider).
7. **Labels loaded once** — `WeightEstimationService.loadLabels()` called once at startup.
8. **Camera permissions required** — handle permission requests gracefully with explanation dialogs.
9. **Image orientation** — photos should be processed regardless of device orientation. The preprocessing pipeline must handle rotation metadata.
10. **No persistent history of estimates** — weight estimation results are ephemeral. They exist only during the session. If persistence is needed later, it would be a separate feature.

---

## 7. TFLite Label Format Analysis

The labels file (`pig_weight_labels.txt`) contains one label per line, each in the format `{number}kg`:

```
100kg
101kg
...
31kg
33kg
```

**Important**: The file is NOT sorted numerically — it appears to be in the order the model was trained. The label at line index `i` corresponds to output class index `i`. The parsing must:

1. Read lines in file order (preserve index mapping).
2. Strip the `kg` suffix to get the numeric weight.
3. The index of the maximum output probability maps to the corresponding line in this file.

---

## 8. Implementation Files (Planned)

| File                                                                  | Layer        | Purpose                            |
| --------------------------------------------------------------------- | ------------ | ---------------------------------- |
| `lib/features/weight/data/models/weight_estimation_model.dart`        | Data         | Weight estimation result (freezed) |
| `lib/features/weight/data/models/price_estimation_model.dart`         | Data         | Price calculation result (freezed) |
| `lib/features/weight/data/services/weight_estimation_service.dart`    | Data         | TFLite inference + label parsing   |
| `lib/features/weight/data/services/price_estimation_service.dart`     | Data         | Weight × SRP calculation           |
| `lib/features/weight/data/providers/weight_providers.dart`            | Data         | Service + state providers          |
| `lib/features/weight/presentation/screens/weight_form_screen.dart`    | Presentation | Photo capture form                 |
| `lib/features/weight/presentation/screens/weight_result_screen.dart`  | Presentation | Result display                     |
| `lib/features/weight/presentation/widgets/photo_capture_card.dart`    | Presentation | Camera/gallery input card          |
| `lib/features/weight/presentation/widgets/weight_result_card.dart`    | Presentation | Weight display                     |
| `lib/features/weight/presentation/widgets/price_estimation_card.dart` | Presentation | Price breakdown                    |

---

## 9. Status

**Data Layer:**

- [ ] WeightEstimationModel (freezed)
- [ ] PriceEstimationModel (freezed)
- [ ] WeightEstimationService (label parsing + inference)
- [ ] PriceEstimationService (weight × SRP)
- [ ] Image preprocessing pipeline
- [ ] Providers (services + state)
- [ ] Model input tensor shape inspection

**Presentation Layer:**

- [ ] WeightFormScreen UI (pending design)
- [ ] WeightResultScreen UI (pending design)
- [ ] PhotoCaptureCard widget (pending design)
- [ ] Camera permission handling
- [ ] Loading/processing indicator
