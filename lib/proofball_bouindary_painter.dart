import 'package:flutter/material.dart';

class ProofBallBoundaryPainter extends StatefulWidget {
  const ProofBallBoundaryPainter({
    super.key,
    required this.rect,
    this.inVisible = false,
    this.onRendered,
  });
  final Rect rect;
  final bool inVisible;
  final VoidCallback? onRendered;
  @override
  State<ProofBallBoundaryPainter> createState() =>
      _ProofBallBoundaryPainterState();
}

class _ProofBallBoundaryPainterState extends State<ProofBallBoundaryPainter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRendered?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: widget.rect,
      child: Container(
        decoration: BoxDecoration(
          border: widget.inVisible
              ? null
              : Border.all(
                  color: Colors.green,
                  width: 2.0,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
