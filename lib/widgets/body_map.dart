import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/muscle_activation.dart';

// A front / back body diagram whose muscle groups are filled according to how
// much volume each absorbed.
//
// Everything is drawn with a CustomPainter rather than an image asset so the
// figure scales cleanly to any screen size and each region can be recoloured
// from data at paint time. Coordinates are normalised (0..1) and multiplied by
// the canvas size, which keeps the layout resolution-independent.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.view,
    required this.activation,
    required this.tierColours,
    required this.emptyColour,
    required this.outlineColour,
  });

  final BodyView view;
  final MuscleActivation activation;
  final Map<ActivationTier, Color> tierColours;

  // Used for the silhouette and for muscles with no logged volume.
  final Color emptyColour;
  final Color outlineColour;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.52,
      child: CustomPaint(
        painter: _BodyPainter(
          view: view,
          activation: activation,
          tierColours: tierColours,
          emptyColour: emptyColour,
          outlineColour: outlineColour,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// One drawable muscle region: a rounded rectangle in normalised space, plus
// its mirror on the other side of the body where the muscle is paired.
class _Region {
  const _Region(this.muscle, this.rect, {this.mirrored = false});

  final Muscle muscle;
  final Rect rect;

  // True for limbs — the same rect is drawn again reflected about x = 0.5.
  final bool mirrored;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.view,
    required this.activation,
    required this.tierColours,
    required this.emptyColour,
    required this.outlineColour,
  });

  final BodyView view;
  final MuscleActivation activation;
  final Map<ActivationTier, Color> tierColours;
  final Color emptyColour;
  final Color outlineColour;

  // Normalised layout, front view. Rect.fromLTRB in 0..1 space.
  static const List<_Region> _front = <_Region>[
    _Region(Muscle.frontDelts, Rect.fromLTRB(0.19, 0.150, 0.33, 0.235),
        mirrored: true),
    _Region(Muscle.chest, Rect.fromLTRB(0.335, 0.155, 0.50, 0.255),
        mirrored: true),
    _Region(Muscle.biceps, Rect.fromLTRB(0.155, 0.245, 0.285, 0.355),
        mirrored: true),
    _Region(Muscle.abs, Rect.fromLTRB(0.375, 0.265, 0.50, 0.445),
        mirrored: true),
    _Region(Muscle.forearms, Rect.fromLTRB(0.125, 0.365, 0.255, 0.475),
        mirrored: true),
    _Region(Muscle.quads, Rect.fromLTRB(0.325, 0.475, 0.485, 0.690),
        mirrored: true),
    _Region(Muscle.calves, Rect.fromLTRB(0.350, 0.705, 0.480, 0.880),
        mirrored: true),
  ];

  // Normalised layout, back view.
  static const List<_Region> _back = <_Region>[
    _Region(Muscle.traps, Rect.fromLTRB(0.355, 0.140, 0.50, 0.245),
        mirrored: true),
    _Region(Muscle.rearDelts, Rect.fromLTRB(0.19, 0.150, 0.345, 0.235),
        mirrored: true),
    _Region(Muscle.lats, Rect.fromLTRB(0.330, 0.250, 0.50, 0.385),
        mirrored: true),
    _Region(Muscle.triceps, Rect.fromLTRB(0.155, 0.245, 0.285, 0.355),
        mirrored: true),
    _Region(Muscle.forearms, Rect.fromLTRB(0.125, 0.365, 0.255, 0.475),
        mirrored: true),
    _Region(Muscle.lowerBack, Rect.fromLTRB(0.385, 0.390, 0.50, 0.455),
        mirrored: true),
    _Region(Muscle.glutes, Rect.fromLTRB(0.340, 0.465, 0.50, 0.560),
        mirrored: true),
    _Region(Muscle.hamstrings, Rect.fromLTRB(0.325, 0.570, 0.485, 0.700),
        mirrored: true),
    _Region(Muscle.calves, Rect.fromLTRB(0.350, 0.710, 0.480, 0.880),
        mirrored: true),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final List<_Region> regions =
        view == BodyView.front ? _front : _back;

    // Head — never coloured, it just makes the figure read as a body.
    final Paint headPaint = Paint()..color = emptyColour;
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.075),
      size.width * 0.115,
      headPaint,
    );
    // Neck.
    _fill(
      canvas,
      size,
      const Rect.fromLTRB(0.435, 0.115, 0.565, 0.165),
      emptyColour,
      radius: 4,
    );

    for (final _Region r in regions) {
      final MuscleLoad? load = activation.loads[r.muscle];
      final Color colour = load == null
          ? emptyColour
          : (tierColours[load.tier] ?? emptyColour);

      _fill(canvas, size, r.rect, colour);
      if (r.mirrored) {
        _fill(canvas, size, _mirror(r.rect), colour);
      }
    }
  }

  // Reflect a rect about the body's vertical centre line.
  Rect _mirror(Rect r) => Rect.fromLTRB(1 - r.right, r.top, 1 - r.left, r.bottom);

  void _fill(
    Canvas canvas,
    Size size,
    Rect normalised,
    Color colour, {
    double radius = 8,
  }) {
    final Rect scaled = Rect.fromLTRB(
      normalised.left * size.width,
      normalised.top * size.height,
      normalised.right * size.width,
      normalised.bottom * size.height,
    );
    // Inset keeps a hairline gap between neighbouring regions so the silhouette
    // reads as separate muscles rather than one solid block.
    final RRect body = RRect.fromRectAndRadius(
      scaled.deflate(1.5),
      Radius.circular(radius),
    );

    canvas.drawRRect(body, Paint()..color = colour);
    canvas.drawRRect(
      body,
      Paint()
        ..color = outlineColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) {
    return old.view != view ||
        old.activation != activation ||
        old.emptyColour != emptyColour;
  }
}
