import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<String> savePickedPhoto(XFile image, String folderName) async {
  final directory = await getApplicationDocumentsDirectory();
  final folder = await Directory('${directory.path}/$folderName')
      .create(recursive: true);
  final path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
  await image.saveTo(path);
  return path;
}

Widget photoImage(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  FilterQuality filterQuality = FilterQuality.low,
  ImageErrorWidgetBuilder? errorBuilder,
}) => Image.file(
  File(path),
  fit: fit,
  width: width,
  height: height,
  filterQuality: filterQuality,
  errorBuilder: errorBuilder,
);
