/// A minimal, dependency-free `Result` type.
///
/// Used at service boundaries so callers are forced to acknowledge failure
/// instead of relying on unchecked exceptions (§39 "async error handling").
library;

import 'app_exceptions.dart';

sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(AppException error) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Value if successful, otherwise `null`.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Error if failed, otherwise `null`.
  AppException? get errorOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final error) => error,
      };

  R fold<R>(R Function(T value) onOk, R Function(AppException error) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final error) => onErr(error),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final error) => Err<R>(error),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppException error;
}

/// Runs [body], converting any throw into an [Err] with a typed code.
///
/// [onError] maps an arbitrary throwable to a user-safe [AppException].
Future<Result<T>> guard<T>(
  Future<T> Function() body,
  AppException Function(Object error, StackTrace stack) onError,
) async {
  try {
    return Ok(await body());
  } on AppException catch (e) {
    return Err(e);
  } catch (e, s) {
    return Err(onError(e, s));
  }
}
