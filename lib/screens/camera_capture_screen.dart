import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../localization/closer_localizations.dart';
import '../models/couple_store.dart';
import '../services/photo_media.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({
    super.key,
    required this.store,
    required this.onClose,
  });
  final CoupleStore store;
  final VoidCallback onClose;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  String? _error, _capturedPath;
  bool _loading = true, _busy = false;
  FlashMode _flashMode = FlashMode.off;
  final _caption = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _caption.dispose();
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final camera = _camera;
      _camera = null;
      if (camera != null) unawaited(camera.dispose());
    } else if (state == AppLifecycleState.resumed && _capturedPath == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera({CameraLensDirection? direction}) async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final previous = _camera;
      _camera = null;
      if (previous != null) await previous.dispose();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found.');
      }
      final selected = direction == null
          ? cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            )
          : cameras.firstWhere(
              (camera) => camera.lensDirection == direction,
              orElse: () => cameras.first,
            );
      final next = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      _camera = next;
      _flashMode = FlashMode.off;
      setState(() => _loading = false);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.description ?? 'Allow camera access in phone settings.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Camera could not open. Check camera permission and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await camera.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Flash is unavailable on this camera.'))),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    final camera = _camera;
    if (camera == null) return;
    final next = camera.description.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await _initializeCamera(direction: next);
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final image = await camera.takePicture();
      await camera.dispose();
      if (identical(_camera, camera)) _camera = null;
      if (mounted) setState(() => _capturedPath = image.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Photo could not be captured. Try again.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final camera = _camera;
    _camera = null;
    if (camera != null) await camera.dispose();
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (photo != null && mounted) {
        setState(() => _capturedPath = photo.path);
      } else if (mounted) {
        await _initializeCamera();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Gallery could not be opened.'))),
        );
        await _initializeCamera();
      }
    }
  }

  Future<void> _saveToMemories() async {
    final path = _capturedPath;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final stablePath = await savePickedPhoto(
        XFile(path),
        folderName: 'closer_memories',
      );
      await widget.store.addMemory(stablePath, _caption.text.trim());
      if (!mounted) return;
      setState(() {
        _capturedPath = null;
        _caption.clear();
        _busy = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Photo added to Memories.'))));
      await _initializeCamera();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo could not be saved: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _capturedPath == null ? _cameraView() : _previewView(),
      ),
    ),
  );

  Widget _cameraView() {
    final camera = _camera;
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Back to Map'),
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                tooltip: _flashMode == FlashMode.off
                    ? 'Flash off'
                    : 'Flash auto',
                onPressed: _toggleFlash,
                icon: Icon(
                  _flashMode == FlashMode.off
                      ? Icons.flash_off_rounded
                      : Icons.flash_auto_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: ColoredBox(
                color: const Color(0xFF171717),
                child: camera != null && camera.value.isInitialized
                    ? SizedBox.expand(child: CameraPreview(camera))
                    : Center(
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Color(0xFF9B70FF),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.no_photography_outlined,
                                    color: Colors.white70,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                    ),
                                    child: Text(
                                      _error ?? 'Camera unavailable',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _initializeCamera,
                                    child: Text(tr('Try again')),
                                  ),
                                ],
                              ),
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 190,
          child: Column(
            children: [
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: tr('All pics'),
                    onPressed: _pickFromGallery,
                    icon: const Icon(
                      Icons.image_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  GestureDetector(
                    onTap: _busy || camera == null ? null : _capture,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 82,
                      height: 82,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF9B70FF),
                          width: 4,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(23),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Switch camera'),
                    onPressed: _switchCamera,
                    icon: const Icon(
                      Icons.flip_camera_android_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: _pickFromGallery,
                child: Text(
                  tr('All pics'),
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewView() => Stack(
    children: [
      Positioned.fill(child: photoImage(_capturedPath!, fit: BoxFit.contain)),
      Positioned(
        top: 4,
        left: 8,
        child: IconButton(
          tooltip: tr('Retake'),
          onPressed: _busy
              ? null
              : () {
                  setState(() => _capturedPath = null);
                  _initializeCamera();
                },
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: 12,
        child: Column(
          children: [
            TextField(
              controller: _caption,
              maxLength: 160,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: tr('Add a caption'),
                hintStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.black.withValues(alpha: .5),
                counterStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _busy ? null : _saveToMemories,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9B70FF),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(tr('Save to Memories')),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
