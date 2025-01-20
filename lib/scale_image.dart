// import 'dart:async';
// import 'package:collection/collection.dart';
// import 'package:flutter/material.dart';
// import 'package:single_image_detection/extension/global_key_extension.dart';
 
// import 'package:single_image_detection/proofball_bouindary_painter.dart';
 
// class CatchExtrapolationImage extends StatefulWidget {
//   final ImageProvider imageProvider;
//   final Feed feed;
//   final bool allowInteraction;
//   const CatchExtrapolationImage({
//     super.key,
//     required this.imageProvider,
//     required this.feed,
//     required this.allowInteraction,
//   });

//   @override
//   State<StatefulWidget> createState() {
//     return CatchExtrapolationImageState();
//   }
// }

// class CatchExtrapolationImageState extends State<CatchExtrapolationImage>
//     with TickerProviderStateMixin {
//   // global key to locate image in tree
//   final GlobalKey _imageKey = GlobalKey();

//   // Offsets calculated after scaling API results to device ratio
 
//   Rect? pballRect;
  

//   Timer? _retryTimer;
//   final int maxRetries = 100;
//   int currentRetry = 0;
//   bool isImageLoaded = false;
//   bool isScaledToDevice = false;
//   double scaleX = 0;
//   double scaleY = 0;
//   double imageDeviceWidth = 0;
//   double imageDeviceHeight = 0;
//   double imageOriginalHeight = 0;
//   double imageOriginalWidth = 0;

 
//   // Function to calculate the scale factors for scaling api points to relative device size
//   void calcImageScaleFactorsAndScaleOffsets() {
//     final imageBounds = _imageKey.globalPaintBounds(null);
//     if (imageBounds == null) return;
//     imageDeviceWidth = imageBounds.size.width;
//     imageDeviceHeight = imageBounds.size.height;
//     final meta = widget.feed.meta;

//     if (meta == null) return;

//     imageOriginalHeight = meta.imageShape?.height?.toDouble() ?? 0.0;
//     imageOriginalWidth = meta.imageShape?.width?.toDouble() ?? 0.0;
//     if (isImageLoaded && !isScaledToDevice && !invalidSize()) {
//       scaleX = imageDeviceWidth / imageOriginalWidth;
//       scaleY = imageDeviceHeight / imageOriginalHeight;
//       scaleApiOffsetsToDeviceSize();
//     }
//   }

//   bool invalidSize() {
//     return imageDeviceWidth == 0 ||
//         imageDeviceHeight == 0 ||
//         imageOriginalHeight == 0 ||
//         imageOriginalWidth == 0;
//   }

//   // Function to scale api points to relative device size
//   void scaleApiOffsetsToDeviceSize() {
//     final fish = widget.feed.fishDetection;
//     final pball = widget.feed.pballDetection;
//     final (pballThresholdConfidence, fishThresholdConfidence) =
//         context.read<RemoteConfigCubit>().confidenceScores();

//     if (fish != null && fish.isNotEmpty) {
//       isFishDetected = fish.first.confidenceScore! > fishThresholdConfidence;
//       final fishOffsets = fish.first.bboxOffsets;
//       final fishOffsetsRelativeToDevice = fishOffsets.map((offset) {
//         return (Offset(offset.dx * scaleX, offset.dy * scaleY));
//       }).toList();

//       fishBoundingRect = Rect.fromPoints(
//         fishOffsetsRelativeToDevice[0],
//         fishOffsetsRelativeToDevice[1],
//       );
//       isVerticalFish = widget.feed.isVerticalFish ?? false;

//       //Keypoints from fish
//       final keypoints = fish.first.keypoints;
//       if (keypoints != null) {
//         keypoints.forEach((key, point) {
//           final parsedKey = int.parse(key);
//           fishKeypoints.addAll({
//             parsedKey: Offset(
//               point[0] * scaleX,
//               point[1] * scaleY,
//             ),
//           });
//         });
//         setlengthKeypointsInDeviceCoordinate();
//       }
//     }
//     if (pball != null && pball.isNotEmpty) {
//       isPballDetected = pball.first.confidenceScore! > pballThresholdConfidence;
//       final pballOffsets = pball.first.bboxOffsets;
//       final pballOffsetsRelativeToDevice = pballOffsets.map((offset) {
//         return (Offset(offset.dx * scaleX, offset.dy * scaleY));
//       }).toList();
//       pballRect = Rect.fromPoints(
//         pballOffsetsRelativeToDevice[0],
//         pballOffsetsRelativeToDevice[1],
//       );
//     }
//     isScaledToDevice = true;
//     calculateMeasurementsInImageCoordinate();
//     setState(() {});
//   }

//   late ImageStreamListener _imageListener;
//   void startRetryUntilSizeDetermined() {
//     _retryTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
//       if (isScaledToDevice || currentRetry >= maxRetries) {
//         _retryTimer?.cancel();
//       } else {
//         calcImageScaleFactorsAndScaleOffsets();
//         currentRetry++;
//       }
//     });
//   }

//   @override
//   void initState() {
//     super.initState();
//     final ImageStream stream =
//         widget.imageProvider.resolve(ImageConfiguration.empty);
//     _imageListener = ImageStreamListener((info, __) {
//       setState(() {
//         isImageLoaded = true;
//       });
//       startRetryUntilSizeDetermined();
//     });
//     stream.addListener(_imageListener);
//   }

//   @override
//   void dispose() {
//     // Remove listener when disposing the widget
//     final ImageStream stream =
//         widget.imageProvider.resolve(ImageConfiguration.empty);
//     stream.removeListener(_imageListener);
//     super.dispose();
//   }

//   void setlengthKeypointsInDeviceCoordinate() {
//     final angle =
//         (fishKeypoints.girthPoints.first - fishKeypoints.girthPoints.last)
//             .direction;
//     isVerticalFish = angleIsVerticle(angle);

//     lengthKeypointsInDeviceCoordinate = fishKeypoints.lengthPoints.sorted(
//         (o1, o2) =>
//             !isVerticalFish ? o1.dx.compareTo(o2.dx) : o1.dy.compareTo(o2.dy));
//     girthKeypointsInDeviceCoordinate = fishKeypoints.girthPoints.sorted(
//         (o1, o2) =>
//             isVerticalFish ? o1.dx.compareTo(o2.dx) : o1.dy.compareTo(o2.dy));
//     setState(() {});
//   }

//   void calculateMeasurementsInImageCoordinate() {
//     lengthOffsetsInImageCoordinate = lengthKeypointsInDeviceCoordinate
//         .map((offset) => Offset(offset.dx / scaleX, offset.dy / scaleY))
//         .toList();
//     girthOffsetsInImageCoordinate = girthKeypointsInDeviceCoordinate
//         .map((offset) => Offset(offset.dx / scaleX, offset.dy / scaleY))
//         .toList();

//     if (pballRect == null) return;
//     pballBoundingRectInImageCoordinate = Rect.fromPoints(
//       Offset((pballRect!.topLeft.dx / scaleX),
//           (pballRect!.topLeft.dy / scaleY)),
//       Offset(
//         (pballRect!.bottomRight.dx / scaleX),
//         (pballRect!.bottomRight.dy / scaleY),
//       ),
//     );
//     if (pballBoundingRectInImageCoordinate == null) return;

//     lengthInterpolation = MeasurementUtils.calculateBallPositionsInImage(
//       keypointsInImageCoordinate: lengthOffsetsInImageCoordinate,
//       pballSizeInImageCoordinate: pballBoundingRectInImageCoordinate!.width,
//       pballSizeInDeviceCoordinate: pballRect!.width,
//       scaleX: scaleX,
//       scaleY: scaleY,
//     );
//     heightInterpolation = MeasurementUtils.calculateBallPositionsInImage(
//       keypointsInImageCoordinate: girthOffsetsInImageCoordinate,
//       pballSizeInImageCoordinate: pballBoundingRectInImageCoordinate!.width,
//       pballSizeInDeviceCoordinate: pballRect!.width,
//       scaleX: scaleX,
//       scaleY: scaleY,
//     );

//     setState(() {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     return !isImageLoaded
//         ? const ImageLoadingShimmer()
//         : Container(
//             color: AppColors.outputDarkBackground,
//             width: double.infinity,
//             child: Center(
//               child: LayoutBuilder(
//                 builder: (BuildContext context, BoxConstraints constraints) {
//                   final scale = (1 - (currentZoomLevel) / (maxZoom))
//                       .clamp(0.1, 1)
//                       .toDouble();
//                   return InteractiveViewer(
//                     panEnabled: widget.allowInteraction,
//                     scaleEnabled: widget.allowInteraction,
//                     minScale: minZoom,
//                     maxScale: maxZoom,
//                     child: Builder(builder: (context) {
//                       return imageStack(scale);
//                     }),
//                   );
//                 },
//               ),
//             ),
//           );
//   }

//   Widget imageStack(double scale) {
//     return Offstage(
//       offstage: !isImageLoaded,
//       child: Stack(
//         alignment: Alignment.center,
//         children: [
//           Container(
//             constraints: BoxConstraints(
//               maxHeight: 0.6 * MediaQuery.of(context).size.height,
//               maxWidth: MediaQuery.of(context).size.width,
//             ),
//             child: Builder(
//               builder: (context) {
//                 return Image(
//                   key: _imageKey,
//                   image: widget.imageProvider,
//                   loadingBuilder: (context, child, loadingProgress) {
//                     if (loadingProgress == null) return child;

//                     return const CircularProgressIndicator();
//                   },
//                   alignment: Alignment.center,
//                   fit: BoxFit.contain,
//                 );
//               },
//             ),
//           ),
//           if (widget.feed.fish != null && isScaledToDevice)
//             ProofBallBoundaryPainter(rect: rect)
//         ],
//       ),
//     );
//   }


// }
