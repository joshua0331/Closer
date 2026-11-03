import 'dart:convert';

import '../services/photo_media.dart';

import 'package:flutter/material.dart';

import '../services/judge_service.dart';

class EvidenceHighlights extends StatefulWidget {
  const EvidenceHighlights({
    super.key,
    required this.path,
    required this.caption,
    required this.judge,
  });
  final String path, caption;
  final JudgeService judge;
  @override
  State<EvidenceHighlights> createState() => _EvidenceHighlightsState();
}

class _EvidenceHighlightsState extends State<EvidenceHighlights> {
  final _prompt = TextEditingController();
  List<Map<String, dynamic>> _boxes = [];
  bool _busy = false, _show = true;
  String? _message;
  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _highlight() async {
    if (_prompt.text.trim().isEmpty) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send this exhibit to Meta SAM?'),
        content: const Text(
          'This sends the original photo and object name through your backend to Meta SAM 3.1. Confirm you have permission. Highlights locate objects; they do not verify authenticity or prove a claim.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send photo'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await readPhoto(widget.path);
      if (bytes.length > 1000000) {
        throw const JudgeException('Choose a photo smaller than 1 MB.');
      }
      final boxes = await widget.judge.segment(
        base64Encode(bytes),
        _prompt.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _show = true;
        _message = boxes.isEmpty
            ? 'SAM found no matching objects.'
            : 'SAM 3.1 · ${boxes.length} object highlight(s).';
      });
    } on JudgeException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not read this photo. The original is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Evidence · original photo')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              photoImage(
                widget.path,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, error, stack) =>
                    const Text('Local evidence file unavailable.'),
              ),
              if (_show)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _BoxPainter(_boxes)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(widget.caption),
          const SizedBox(height: 16),
          const Text(
            'Optional object highlights',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Name one visible object, such as “plate” or “phone”. Boxes are visual guides, not proof. The AI can point out visible details, but cannot verify the story.',
          ),
          TextField(
            controller: _prompt,
            maxLength: 80,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Object to highlight'),
          ),
          FilledButton.icon(
            onPressed: _busy || !widget.judge.configured ? null : _highlight,
            icon: const Icon(Icons.center_focus_strong),
            label: Text(_busy ? 'Finding objects…' : 'Highlight with SAM 3.1'),
          ),
          if (!widget.judge.configured)
            const Text('Sign in and pair with your partner to use SAM.'),
          if (_boxes.isNotEmpty)
            SwitchListTile(
              title: const Text('Show highlights'),
              value: _show,
              onChanged: (value) => setState(() => _show = value),
            ),
          if (_message != null) Text(_message!),
        ],
      ),
    ),
  );
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes);
  final List<Map<String, dynamic>> boxes;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF18F77)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final box in boxes) {
      canvas.drawRect(
        Rect.fromLTRB(
          (box['left'] as num).toDouble() * size.width,
          (box['top'] as num).toDouble() * size.height,
          (box['right'] as num).toDouble() * size.width,
          (box['bottom'] as num).toDouble() * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
