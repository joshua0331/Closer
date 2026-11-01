import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_native.dart'
    if (dart.library.js_interop) 'photo_web.dart'
    as platform;

Future<Uint8List> readPhoto(String path) async => path.startsWith('data:')
    ? base64Decode(path.substring(path.indexOf(',') + 1))
    : XFile(path).readAsBytes();

Future<String> savePickedPhoto(XFile image, {required String folderName}) =>
    platform.savePickedPhoto(image, folderName);

Widget photoImage(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  FilterQuality filterQuality = FilterQuality.low,
  ImageErrorWidgetBuilder? errorBuilder,
}) => path.startsWith('data:')
    ? Image.memory(
        base64Decode(path.substring(path.indexOf(',') + 1)),
        fit: fit,
        width: width,
        height: height,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
      )
    : platform.photoImage(
        path,
        fit: fit,
        width: width,
        height: height,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
      );
