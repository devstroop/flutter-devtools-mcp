import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/actions.dart';

void main() {
  group('NodeBounds', () {
    test('centerX and centerY calculate correctly', () {
      final bounds = NodeBounds(x: 100, y: 200, width: 50, height: 30);
      expect(bounds.centerX, 125.0);
      expect(bounds.centerY, 215.0);
    });

    test('toJson produces correct map', () {
      final bounds = NodeBounds(x: 10, y: 20, width: 30, height: 40);
      expect(bounds.toJson(), {'x': 10.0, 'y': 20.0, 'w': 30.0, 'h': 40.0});
    });
  });

  group('ActionabilityResult', () {
    test('actionable when all flags true', () {
      final result = ActionabilityResult(
        visible: true,
        hitTestable: true,
        inViewport: true,
        enabled: true,
      );
      expect(result.actionable, true);
      expect(result.reason, 'actionable');
    });

    test('not actionable when not visible', () {
      final result = ActionabilityResult(
        visible: false,
        hitTestable: true,
        inViewport: true,
        enabled: true,
      );
      expect(result.actionable, false);
      expect(result.reason, contains('not visible'));
    });

    test('not actionable when not hit testable', () {
      final result = ActionabilityResult(
        visible: true,
        hitTestable: false,
        inViewport: true,
        enabled: true,
      );
      expect(result.actionable, false);
      expect(result.reason, contains('obscured'));
    });

    test('not actionable when outside viewport', () {
      final result = ActionabilityResult(
        visible: true,
        hitTestable: true,
        inViewport: false,
        enabled: true,
      );
      expect(result.actionable, false);
      expect(result.reason, contains('viewport'));
    });

    test('not actionable when disabled', () {
      final result = ActionabilityResult(
        visible: true,
        hitTestable: true,
        inViewport: true,
        enabled: false,
      );
      expect(result.actionable, false);
      expect(result.reason, contains('disabled'));
    });

    test('reason reports first failing check in priority order', () {
      final result = ActionabilityResult(
        visible: false,
        hitTestable: false,
        inViewport: false,
        enabled: false,
      );
      // visible is checked first
      expect(result.reason, contains('not visible'));
    });
  });
}
