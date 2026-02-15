/// A simple Result type for representing success/failure.
///
/// Usage:
/// ```dart
/// final result = await someApiCall();
/// result.when(
///   success: (data) => print(data),
///   failure: (error) => print(error.message),
/// );
/// ```
sealed class Result<S, E> {
  const Result._();

  const factory Result.success(S value) = Success<S, E>;
  const factory Result.failure(E error) = Failure<S, E>;

  /// Pattern-match on success / failure.
  T when<T>({
    required T Function(S value) success,
    required T Function(E error) failure,
  }) {
    return switch (this) {
      Success(:final value) => success(value),
      Failure(:final error) => failure(error),
    };
  }

  bool get isSuccess => this is Success<S, E>;
  bool get isFailure => this is Failure<S, E>;
}

final class Success<S, E> extends Result<S, E> {
  const Success(this.value) : super._();
  final S value;
}

final class Failure<S, E> extends Result<S, E> {
  const Failure(this.error) : super._();
  final E error;
}
