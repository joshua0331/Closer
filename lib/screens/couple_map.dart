import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const peach = Color(0xFFF18F77);
const ivory = Color(0xFFFFF9F0);
const slate = Color(0xFF424A52);

class CoupleMap extends StatefulWidget {
  const CoupleMap({
    super.key,
    required this.yourName,
    required this.partnerName,
    required this.onProfile,
    required this.onNotifications,
    required this.onDate,
    this.startedOn,
  });
  final String yourName, partnerName;
  final VoidCallback onProfile, onNotifications, onDate;
  final DateTime? startedOn;
  @override
  State<CoupleMap> createState() => _CoupleMapState();
}

class _CoupleMapState extends State<CoupleMap> {
  late final Future<List<List<Offset>>> _outlines = _loadOutlines();

  Future<List<List<Offset>>> _loadOutlines() async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/maps/countries.geojson'),
    ) as Map<String, dynamic>;
    final polygons = <List<Offset>>[];
    for (final feature in data['features'] as List) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final groups = geometry['type'] == 'Polygon'
          ? [coordinates]
          : coordinates;
      for (final polygon in groups) {
        // Exterior rings are sufficient for the small-scale decorative preview.
        final ring = (polygon as List).first as List;
        polygons.add(
          ring
              .map(
                (point) => Offset(
                  (point[0] as num).toDouble(),
                  (point[1] as num).toDouble(),
                ),
              )
              .toList(),
        );
      }
    }
    return polygons;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final top = MediaQuery.paddingOf(context).top + 20;
      return Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<List<List<Offset>>>(
              future: _outlines,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ColoredBox(
                    color: Color(0xFF9BD8DC),
                    child: Center(child: Text('Map preview unavailable')),
                  );
                }
                if (!snapshot.hasData) {
                  return const ColoredBox(
                    color: Color(0xFF9BD8DC),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 3,
                  child: CustomPaint(
                    painter: _MapPainter(
                      snapshot.data!,
                      widget.yourName,
                      widget.partnerName,
                    ),
                    size: Size(width, constraints.maxHeight),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: top,
            left: 16,
            child: _roundButton(
              Icons.settings_outlined,
              'Our profile',
              widget.onProfile,
            ),
          ),
          Positioned(
            top: top,
            right: 16,
            child: _roundButton(
              Icons.notifications_none_rounded,
              'Notifications',
              widget.onNotifications,
            ),
          ),
          Positioned(
            top: top - 3,
            left: width * .23,
            right: width * .23,
            child: Semantics(
              button: true,
              label: 'Set relationship date',
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: widget.onDate,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  decoration: BoxDecoration(
                    color: ivory,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: peach.withValues(alpha: .8),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x142E6668),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Closer',
                        style: TextStyle(
                          letterSpacing: 4,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: slate,
                        ),
                      ),
                      const _Hearts(),
                      const SizedBox(height: 4),
                      Text(
                        widget.startedOn == null ? 'Our story' : 'Together for',
                        style: const TextStyle(fontSize: 16, color: slate),
                      ),
                      const SizedBox(height: 2),
                      if (widget.startedOn == null)
                        const Text(
                          'Add your date',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: slate,
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(widget.startedOn!)).inDays}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 25,
                                ),
                              ),
                              const TextSpan(
                                text: ' days',
                                style: TextStyle(fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 128 + MediaQuery.paddingOf(context).bottom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: ivory.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Illustrative map · Locations not connected',
                style: TextStyle(color: slate, fontSize: 11),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 110 + MediaQuery.paddingOf(context).bottom,
            child: const Text(
              'Map outlines: Natural Earth',
              style: TextStyle(fontSize: 9, color: Color(0xFF385D63)),
            ),
          ),
        ],
      );
    },
  );

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Container(
        decoration: BoxDecoration(
          color: ivory,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFDAC5), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x143F7175),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onTap,
          tooltip: tooltip,
          icon: Icon(icon, color: slate, size: 28),
          padding: const EdgeInsets.all(12),
        ),
      );
}

class _Hearts extends StatelessWidget {
  const _Hearts();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 52,
    height: 24,
    child: Stack(
      children: [
        Positioned(
          left: 8,
          child: Icon(Icons.favorite_border_rounded, size: 26, color: peach),
        ),
        Positioned(
          left: 23,
          child: Icon(Icons.favorite_border_rounded, size: 26, color: peach),
        ),
      ],
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.polygons, this.yourName, this.partnerName);
  final List<List<Offset>> polygons;
  final String yourName, partnerName;

  Offset project(Offset coordinate, Size size) {
    // Fixed illustrative Southeast Asia / Australia viewport, independent of GPS.
    return Offset(
      (coordinate.dx - 86) / 62 * size.width,
      (40 - coordinate.dy) / 90 * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB4E4E0), Color(0xFF8ED2DA), Color(0xFFADDCDD)],
        ).createShader(Offset.zero & size),
    );
    for (final polygon in polygons) {
      final path = Path();
      for (var i = 0; i < polygon.length; i++) {
        final point = project(polygon[i], size);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFF7F1E3));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFCEE3C8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFAFCBB5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .45,
      );
    }
    for (final label in <(String, double, double)>[
      ('China', 104, 33),
      ('South Korea', 130, 35),
      ('Thailand', 100, 16),
      ('Vietnam', 108, 12),
      ('Malaysia', 102, 3),
      ('Philippines', 126, 9),
      ('Indonesia', 116, -7),
      ('Australia', 133, -28),
    ]) {
      _text(
        canvas,
        label.$1,
        project(Offset(label.$2, label.$3), size),
        12,
        slate,
        weight: FontWeight.w600,
      );
    }
    _text(
      canvas,
      'South China\nSea',
      project(const Offset(113, 16), size),
      11,
      const Color(0xFF568A95),
    );
    _text(
      canvas,
      'Philippine Sea',
      project(const Offset(138, 19), size),
      11,
      const Color(0xFF568A95),
    );
    _text(
      canvas,
      'Banda Sea',
      project(const Offset(133, -9), size),
      11,
      const Color(0xFF568A95),
    );
    final first = project(const Offset(121.5, 18), size);
    final second = project(const Offset(113, -6), size);
    final vector = second - first;
    final length = vector.distance;
    for (double distance = 36; distance < length - 30; distance += 17) {
      final start = first + vector * (distance / length);
      final end =
          first + vector * (math.min(distance + 7, length - 30) / length);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = peach
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    _avatar(canvas, first, yourName.isEmpty ? 'You' : yourName, peach);
    _avatar(
      canvas,
      second,
      partnerName.isEmpty ? 'Partner' : partnerName,
      const Color(0xFF759F9C),
    );
    _chip(
      canvas,
      first + const Offset(0, -61),
      Icons.home_outlined,
      'Home · sample',
    );
    _chip(
      canvas,
      second + const Offset(0, -61),
      Icons.work_outline_rounded,
      'Work · sample',
    );
  }

  void _avatar(Canvas canvas, Offset center, String name, Color color) {
    canvas.drawCircle(
      center + const Offset(0, 5),
      28,
      Paint()
        ..color = const Color(0x18486768)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(center, 27, Paint()..color = ivory);
    canvas.drawCircle(center, 24, Paint()..color = color);
    _text(
      canvas,
      name.characters.first.toUpperCase(),
      center - const Offset(0, 2),
      26,
      ivory,
    );
    canvas.drawCircle(center + const Offset(0, 31), 4, Paint()..color = ivory);
    canvas.drawCircle(
      center + const Offset(0, 31),
      2.5,
      Paint()..color = color,
    );
  }

  void _chip(Canvas canvas, Offset center, IconData icon, String label) {
    final rect = Rect.fromCenter(center: center, width: 132, height: 36);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(15)),
      Paint()..color = ivory,
    );
    canvas.drawCircle(
      Offset(rect.left + 19, center.dy),
      14,
      Paint()..color = const Color(0xFFFFDFC9),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 19,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: slate,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(rect.left + 9.5, center.dy - painter.height / 2),
    );
    _text(
      canvas,
      label,
      Offset(center.dx + 15, center.dy),
      11,
      slate,
      weight: FontWeight.w600,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.normal,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'CoupleSans',
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.polygons != polygons ||
      old.yourName != yourName ||
      old.partnerName != partnerName;
}

class CoupleDock extends StatelessWidget {
  const CoupleDock({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  static const labels = ['Map', 'Court', 'Memories', 'Chat', 'Closer'];
  static const icons = [
    Icons.add_location_alt_outlined,
    Icons.gavel_rounded,
    Icons.photo_library_outlined,
    Icons.forum_outlined,
    Icons.favorite_border_rounded,
  ];
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(10, 0, 10, 12),
    child: Container(
      height: 88,
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFFFE9DA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x193E6667),
            blurRadius: 24,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: List.generate(
          labels.length,
          (index) => Expanded(
            child: Semantics(
              selected: selected == index,
              button: true,
              label: labels[index],
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(28),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 48,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected == index
                              ? const Color(0xFFFFDFCD)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(icons[index], size: 28, color: slate),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        labels[index],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected == index
                              ? const Color(0xFFB85842)
                              : slate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 3,
                        width: 15,
                        decoration: BoxDecoration(
                          color: selected == index ? peach : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
