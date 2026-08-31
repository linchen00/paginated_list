import 'dart:async';

import 'package:flutter/foundation.dart';

/// 保存单个方向正在执行的请求，并用代次令牌识别已经失效的动画。
class PaginatedRequestSlot {
  Future<void>? _inFlight;
  int _generation = 0;

  Future<void>? get inFlight => _inFlight;

  Future<void> start(Future<void> Function(bool Function() isCurrent) action) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final generation = ++_generation;
    final completer = Completer<void>();
    final future = completer.future;
    _inFlight = future;
    Future<void>.sync(
      () => action(() => generation == _generation),
    ).then(completer.complete, onError: completer.completeError);
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    }).ignore();
    return future;
  }

  /// 使动画失效；换绑时同时解除 Future 复用关系。
  void invalidate({bool detach = false}) {
    _generation++;
    if (detach) _inFlight = null;
  }
}

/// 串行化同一视口上两个方向的展示动画。
class PaginatedRequestCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(AsyncCallback action) {
    final completer = Completer<void>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        await action();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
