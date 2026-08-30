import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

typedef IndicatorLayoutCallback =
    void Function(double mainAxisExtent, ScrollPosition? position);

/// 测量 Indicator 实际主轴尺寸，并暴露其所属 ScrollPosition。
class PaginatedIndicatorHost extends StatefulWidget {
  const PaginatedIndicatorHost({
    super.key,
    required this.axis,
    required this.onLayout,
    required this.child,
  });

  final Axis axis;
  final IndicatorLayoutCallback onLayout;
  final Widget child;

  @override
  State<PaginatedIndicatorHost> createState() => _PaginatedIndicatorHostState();
}

class _PaginatedIndicatorHostState extends State<PaginatedIndicatorHost> {
  bool _reportScheduled = false;
  double? _lastExtent;
  ScrollPosition? _lastPosition;

  void _reportAfterLayout() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted) return;
      final size = context.size;
      final extent = widget.axis == Axis.vertical
          ? (size?.height ?? 0)
          : (size?.width ?? 0);
      final position = Scrollable.maybeOf(context)?.position;
      if (_lastExtent == extent && identical(_lastPosition, position)) return;
      _lastExtent = extent;
      _lastPosition = position;
      widget.onLayout(extent, position);
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportAfterLayout();
    return widget.child;
  }
}
