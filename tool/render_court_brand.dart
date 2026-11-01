import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:closer/screens/couple_court_brand.dart';

void main() {
  test(
    'Export the native Couple Court vector mark for web installation',
    () async {
      for (final size in [32, 192, 512]) {
        final recorder = ui.PictureRecorder();
        const CourtMarkPainter().paint(
          Canvas(recorder),
          Size.square(size.toDouble()),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        if (size == 32) {
          File('web/favicon.png').writeAsBytesSync(bytes);
        } else {
          for (final name in ['Icon-$size.png', 'Icon-maskable-$size.png']) {
            File('web/icons/$name').writeAsBytesSync(bytes);
          }
        }
        image.dispose();
        picture.dispose();
      }
    },
  );
}
