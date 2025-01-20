import 'package:flutter/material.dart';

extension GlobalKeyExtension on GlobalKey {
  Rect? globalPaintBounds(RenderObject? ancestor) {
    final renderObject = currentContext?.findRenderObject();
    if (renderObject != null) {
      final translation =
          renderObject.getTransformTo(ancestor).getTranslation();
      final offset = Offset(translation.x, translation.y);
      return renderObject.paintBounds.shift(offset);
    }
    return null;
  }
}
