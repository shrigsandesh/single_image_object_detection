// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:single_image_detection/extension/global_key_extension.dart';

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
  late Interpreter pballInterpreter;
  late Interpreter fishInterpreter;

  late IsolateInterpreter pballIsolate;
  late IsolateInterpreter fishIsolate;
  bool isLoading = true;
  List<Detection> objDetections = [];

  final GlobalKey _imageKey = GlobalKey();
  late ImageProvider imageProvider;
  late ImageStreamListener _imageListener;

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

  List input = [];
  List output = [];

  @override
  void initState() {
    super.initState();
    imageProvider = const AssetImage("assets/images/proofball.png");
    loadModel();
    final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
    _imageListener = ImageStreamListener((info, __) {
      setState(() {
        isImageLoaded = true;
      });
      resizeImageToInput(image: info.image);
      startRetryUntilSizeDetermined(info: info);
    });
    stream.addListener(_imageListener);
  }

  // Function to calculate the scale factors for scaling api points to relative device size
  void calcImageScaleFactorsAndScaleOffsets({
    required ImageInfo info,
  }) {
    final imageBounds = _imageKey.globalPaintBounds(null);
    if (imageBounds == null) return;
    imageDeviceWidth = imageBounds.size.width;
    imageDeviceHeight = imageBounds.size.height;

    imageOriginalHeight = info.image.height.toDouble();
    imageOriginalWidth = info.image.width.toDouble();
  }

  void startRetryUntilSizeDetermined({
    required ImageInfo info,
  }) {
    _retryTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (isScaledToDevice || currentRetry >= maxRetries) {
        _retryTimer?.cancel();
      } else {
        calcImageScaleFactorsAndScaleOffsets(
          info: info,
        );
        currentRetry++;
      }
    });
  }

  @override
  void dispose() {
    final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
    stream.removeListener(_imageListener);
    fishInterpreter.close();
    pballInterpreter.close();
    super.dispose();
  }

  Future<void> loadModel() async {
    try {
      setState(() {
        isLoading = true;
      });
      pballInterpreter =
          await Interpreter.fromAsset("assets/ml/pball_model.tflite");
      fishInterpreter =
          await Interpreter.fromAsset("assets/ml/fish_detection.tflite");

      pballIsolate =
          await IsolateInterpreter.create(address: pballInterpreter.address);
      fishIsolate =
          await IsolateInterpreter.create(address: fishInterpreter.address);
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      log('Error loading model: $e');
    }
  }

  Future<void> resizeImageToInput({
    required ui.Image image,
  }) async {
    final ByteData? bytedata =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytedata == null) return;
    final originalImage = img.decodeImage(
      bytedata.buffer.asUint8List(
        bytedata.offsetInBytes,
        bytedata.lengthInBytes,
      ),
    );

    if (originalImage == null) throw Exception('Failed to load image');

    // Resize image to 640x640
    final resizedImage = img.copyResize(
      originalImage,
      width: 640,
      height: 640,
      interpolation: img.Interpolation.linear,
    ); // Create input tensor
    input = List.generate(
      1,
      (index) => List.generate(
        640,
        (y) => List.generate(
          640,
          (x) => List.generate(
            3,
            (c) {
              final pixel = resizedImage.getPixel(x, y);
              double value = 0;
              if (c == 0) {
                value = pixel.r.toDouble();
              } else if (c == 1) {
                value = pixel.g.toDouble();
              } else {
                value = pixel.b.toDouble();
              }
              return value / 255.0;
            },
          ),
        ),
      ),
    );

    output = List.filled(1 * 300 * 6, 0).reshape([1, 300, 6]);
  }

  Future<void> detect(Interpreter interpreter, bool pballInterpreter) async {
    try {
      if (pballInterpreter) {
        await pballIsolate.run(input, output);
      } else {
        await fishIsolate.run(input, output);
      }

      final score = output[0][0][4] as double?;
      if (score == null) return;
      double x1 = output[0][0][0] * imageDeviceWidth;
      double y1 = output[0][0][1] * imageDeviceHeight;
      double x2 = output[0][0][2] * imageDeviceWidth;
      double y2 = output[0][0][3] * imageDeviceHeight;

      Detection detection = Detection(
        confidence: score,
        rect: Rect.fromPoints(
          Offset(x1, y1),
          Offset(x2, y2),
        ),
      );

      objDetections.add(detection);

      setState(() {});
    } catch (e) {
      log('Error processing image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TFLite Object Detection'),
      ),
      body: Center(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      color: Colors.black,
                      width: double.infinity,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: Stack(
                          children: [
                            Image(
                              key: _imageKey,
                              image: imageProvider,
                              fit: BoxFit.contain,
                            ),
                            if (objDetections.isNotEmpty)
                              ...List.generate(
                                objDetections.length,
                                (index) => BoundaryBoxBorder(
                                  rect: objDetections[index].rect,
                                  borderColor: Colors.green,
                                  borderWidth: 3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        detect(fishInterpreter, false);
                        detect(pballInterpreter, true);
                      },
                      child: const Text('Detect Objects'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}

class Detection {
  final double confidence;
  final Rect rect;
  Detection({
    required this.confidence,
    required this.rect,
  });
}

class BoundaryBoxBorder extends StatelessWidget {
  final Rect rect;
  final Color borderColor;
  final double borderWidth;

  const BoundaryBoxBorder({
    super.key,
    required this.rect,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
        rect: rect,
        child: CustomPaint(
          foregroundPainter: FishBoundaryBoxScannerBorderPainter(
            borderColor,
            borderWidth,
          ),
        ));
  }
}

// Modified to use topLeft and bottomRight for rectangle
class FishBoundaryBoxScannerBorderPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;

  FishBoundaryBoxScannerBorderPainter(this.borderColor, this.borderWidth);

  @override
  void paint(Canvas canvas, Size size) {
    const width = 2.0;
    const radius = 2.5;
    const tRadius = 3 * radius;
    final rect = Rect.fromLTWH(
      width,
      width,
      size.width - 2 * width,
      size.height - 2 * width,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(radius));
    const clippingRect0 = Rect.fromLTWH(
      0,
      0, // Adjust these values for desired gap
      2.7 * tRadius,
      tRadius, // Increase height for top gap
    );

    final clippingRect1 = Rect.fromLTWH(
      size.width - 2.7 * tRadius, // Adjusted width for longer top left side
      0,
      2.7 * tRadius,
      tRadius,
    );
    final clippingRect2 = Rect.fromLTWH(
      0,
      size.height - tRadius,
      tRadius * 2.7,
      tRadius,
    );
    final clippingRect3 = Rect.fromLTWH(
      size.width - 2.7 * tRadius,
      size.height - tRadius,
      tRadius * 2.7,
      tRadius,
    );
    final path = Path()
      ..addRect(clippingRect0)
      ..addRect(clippingRect1)
      ..addRect(clippingRect2)
      ..addRect(clippingRect3);

    canvas.clipPath(path);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
