import 'package:flutter/foundation.dart';

import 'internal/paginated_binding.dart';

/// 可选的视图控制入口，不持有分页数据或业务状态。
class PaginatedController {
  PaginatedBinding? _binding;
  bool _disposed = false;

  bool get isAttached => _binding != null;

  Future<void> requestRefresh() => _request(leading: true);
  Future<void> requestLoading() => _request(leading: false);

  Future<void> _request({required bool leading}) {
    if (_disposed) {
      return Future.error(StateError('PaginatedController 已 dispose。'));
    }
    final binding = _binding;
    if (binding == null) {
      return Future.error(
        PaginatedBindingErrors.notBound(
          leading ? 'requestRefresh()' : 'requestLoading()',
        ),
      );
    }
    return leading ? binding.requestRefresh() : binding.requestLoading();
  }

  @internal
  void bind(PaginatedBinding binding) {
    if (_disposed) throw StateError('已 dispose 的 PaginatedController 不能绑定。');
    if (_binding != null && !identical(_binding, binding)) {
      throw FlutterError('一个 PaginatedController 同一时刻只能绑定一个 PaginatedList。');
    }
    _binding = binding;
  }

  @internal
  void unbind(PaginatedBinding binding) {
    if (identical(_binding, binding)) _binding = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final binding = _binding;
    _binding = null;
    binding?.cancelControllerRequests();
  }
}
