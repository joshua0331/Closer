import '../services/photo_media.dart';

import 'package:flutter/material.dart';

class CourtroomScene extends StatelessWidget {
  const CourtroomScene({
    super.key,
    this.generatedScene,
    required this.names,
    this.active = -1,
  });
  final String? generatedScene;
  final List<String> names;
  final int active;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1672 / 941,
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(
            child: generatedScene == null
                ? Image.asset(
                    'assets/court/courtroom.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                  )
                : photoImage(
                    generatedScene!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, error, stack) => const Center(
                      child: Text(
                        'Saved artwork is unavailable. Generate a new scene.',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
          for (var i = 0; i < 2; i++)
            Positioned(
              left: box.maxWidth * (i == 0 ? .10 : .72),
              bottom: box.maxHeight * .16,
              width: box.maxWidth * .18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: active == i
                      ? const Color(0xFFFFCF76)
                      : const Color(0xDD38241D),
                  border: Border.all(color: const Color(0xFFC79555)),
                ),
                child: Text(
                  names[i].isEmpty ? 'Partner ${i + 1}' : names[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (box.maxWidth / 44).clamp(9, 16),
                    fontWeight: FontWeight.bold,
                    color: active == i
                        ? const Color(0xFF38241D)
                        : const Color(0xFFFFE3AE),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
