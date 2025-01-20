import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:single_image_detection/extension/global_key_extension.dart';
import 'package:single_image_detection/proofball_bouindary_painter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TFLite Object Detection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ObjectDetectionPage(),
    );
  }
}

class ObjectDetectionPage extends StatefulWidget {
  const ObjectDetectionPage({super.key});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
  late Interpreter interpreter;
  bool isLoading = true;
  List<Map<String, dynamic>> detections = [];

  final GlobalKey _imageKey = GlobalKey();
  ImageProvider? imageProvider;
  late ImageStreamListener _imageListener;

  // Offsets calculated after scaling API results to device ratio

  Rect? pballRect;

  Timer? _retryTimer;
  final int maxRetries = 100;
  int currentRetry = 0;
  bool isImageLoaded = false;
  bool isScaledToDevice = false;
  double scaleX = 0;
  double scaleY = 0;
  double imageDeviceWidth = 0;
  double imageDeviceHeight = 0;
  double imageOriginalHeight = 0;
  double imageOriginalWidth = 0;
  Size imagesize = Size.zero;

  void calcImageScaleFactorsAndScaleOffsets(
      {required double imageOriginalHeight,
      required double imageOriginalWidth,
      required Rect rect}) {
    final imageBounds = _imageKey.globalPaintBounds(null);
    if (imageBounds == null) return;

    if (isImageLoaded && !invalidSize()) {
      scaleX = imageBounds.width / imageOriginalWidth;
      scaleY = imageBounds.height / imageOriginalHeight;

      pballRect = Rect.fromLTRB(rect.left * scaleX, rect.top * scaleY,
          rect.right * scaleX, rect.bottom * scaleY);

      setState(() {});
    }
  }

  bool invalidSize() {
    return imageDeviceWidth == 0 ||
        imageDeviceHeight == 0 ||
        imageOriginalHeight == 0 ||
        imageOriginalWidth == 0;
  }

  @override
  void initState() {
    super.initState();

    loadModel();
  }

  void calculateScaledBoundingBox(List<double> bbox, Size originalSize) {
    final RenderBox? renderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Size displaySize = renderBox.size;

    // Calculate scale factors
    double scaleX = displaySize.width / originalSize.width;
    double scaleY = displaySize.height / originalSize.height;

    // Use the smaller scale factor to maintain aspect ratio
    double scale = scaleX < scaleY ? scaleX : scaleY;

    // Calculate padding to center the image
    double horizontalPadding =
        (displaySize.width - (originalSize.width * scale)) / 2;
    double verticalPadding =
        (displaySize.height - (originalSize.height * scale)) / 2;

    // Scale and translate the bounding box
    double scaledX1 = (bbox[0] * scale) + horizontalPadding;
    double scaledY1 = (bbox[1] * scale) + verticalPadding;
    double scaledX2 = (bbox[2] * scale) + horizontalPadding;
    double scaledY2 = (bbox[3] * scale) + verticalPadding;

    setState(() {
      pballRect = Rect.fromLTRB(scaledX1, scaledY1, scaledX2, scaledY2);
    });
  }

  Future<void> loadModel() async {
    try {
      // ignore: unnecessary_string_escapes
      interpreter =
          await Interpreter.fromAsset("assets/ml/fish_detection.tflite");
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  Future<void> processImage(Size size) async {
    try {
      final ByteData imageData =
          await rootBundle.load('assets/images/proofball.png');
      final Uint8List bytes = imageData.buffer.asUint8List(
        imageData.offsetInBytes,
        imageData.lengthInBytes,
      );
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) throw Exception('Failed to load image');

      final int originalWidth = originalImage.width;
      final int originalHeight = originalImage.height;

      var imageSize = Size(originalWidth.toDouble(), originalHeight.toDouble());

      // Resize image to 640x640
      final img.Image resizedImage = img.copyResize(
        originalImage,
        width: 640,
        height: 640,
        interpolation: img.Interpolation.cubic,
      );

      // Create input tensor
      var input = List.generate(
        1,
        (index) => List.generate(
          640,
          (y) => List.generate(
            640,
            (x) => List.generate(
              3,
              (c) {
                final pixel = resizedImage.getPixel(x, y);
                return c == 0
                    ? pixel.r.toDouble() / 255.0
                    : c == 1
                        ? pixel.g.toDouble() / 255.0
                        : pixel.b.toDouble() / 255.0;
              },
            ),
          ),
        ),
      );

      var output = List.filled(1 * 300 * 6, 0).reshape([1, 300, 6]);
      interpreter.run(input, output);

      List<Map<String, dynamic>> processedDetections = [];

      for (var i = 0; i < 5; i++) {
        final score = output[0][i][4];
        if (score > 0.5) {
          double x1 = output[0][i][0] * originalWidth;
          double y1 = output[0][i][1] * originalHeight;
          double x2 = output[0][i][2] * originalWidth;
          double y2 = output[0][i][3] * originalHeight;

          processedDetections.add({
            'class_id': output[0][i][5].toInt(),
            'confidence': score,
            'bbox': [x1, y1, x2, y2],
            'original_dimensions': {
              'width': originalWidth,
              'height': originalHeight,
            }
          });

          // Calculate scaled bounding box for display
          if (imageSize != null) {
            calculateScaledBoundingBox([x1, y1, x2, y2], imageSize!);
          }
        }
      }

      setState(() {
        detections = processedDetections;
      });

      await initializeImage(bytes);
    } catch (e) {
      print('Error processing image: $e');
      setState(() {
        detections = [];
      });
    }
  }

  Future<void> initializeImage(Uint8List data) async {
    imageProvider = MemoryImage(data);
    if (imageProvider == null) return;
    final ImageStream stream = imageProvider!.resolve(ImageConfiguration.empty);
    _imageListener = ImageStreamListener((info, __) {
      if (mounted) {
        setState(() {
          isImageLoaded = true;
        });
      }
    });
    stream.addListener(_imageListener);
  }

  @override
  void dispose() {
    interpreter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TFLite Object Detection'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              Center(child: const CircularProgressIndicator())
            else
              Expanded(
                child: Column(
                  children: [
                    // imageStack(1.0),

                    Image.asset(
                      'assets/images/proofball.png',
                      height: 400,
                      width: 400,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Detections: ${detections.length}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: detections.length,
                        itemBuilder: (context, index) {
                          final detection = detections[index];
                          return ListTile(
                            title: Text(
                              'Class ${detection['class_id']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                                'Confidence: ${(detection['confidence'] * 100).toStringAsFixed(2)}%\n'
                                'BBox: [${detection['bbox'].map((e) => e.toStringAsFixed(3)).join(", ")}]'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () =>
                          processImage(MediaQuery.of(context).size),
                      child: const Text('Detect Objects'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget imageStack(double scale) {
  //   return Offstage(
  //     offstage: !isImageLoaded,
  //     child: Stack(
  //       alignment: Alignment.center,
  //       children: [
  //         Container(
  //           constraints: BoxConstraints(
  //             maxHeight: 0.6 * MediaQuery.of(context).size.height,
  //             maxWidth: MediaQuery.of(context).size.width,
  //           ),
  //           child: Builder(
  //             builder: (context) {
  //               return Image(
  //                 key: _imageKey,
  //                 image: imageProvider!,
  //                 loadingBuilder: (context, child, loadingProgress) {
  //                   if (loadingProgress == null) return child;

  //                   return const CircularProgressIndicator();
  //                 },
  //                 alignment: Alignment.center,
  //                 fit: BoxFit.contain,
  //               );
  //             },
  //           ),
  //         ),
  //         if (pballRect != null) ProofBallBoundaryPainter(rect: pballRect!)
  //       ],
  //     ),
  //   );
  // }
}
