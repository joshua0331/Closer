import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<String> savePickedPhoto(XFile image, String folderName) async =>
    'data:image/jpeg;base64,${base64Encode(await image.readAsBytes())}';

Widget photoImage(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  FilterQuality filterQuality = FilterQuality.low,
  ImageErrorWidgetBuilder? errorBuilder,
}) => Image.network(
  path,
  fit: fit,
  width: width,
  height: height,
  filterQuality: filterQuality,
  errorBuilder: errorBuilder,
);
