import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/selectors.dart';

void main() {
  group('Selector.parse', () {
    test('parses semantics selector', () {
      final s = Selector.parse('semantics:Submit');
      expect(s.tier, SelectorTier.semantics);
      expect(s.value, 'Submit');
      expect(s.index, isNull);
    });

    test('parses key selector', () {
      final s = Selector.parse('key:submit_btn');
      expect(s.tier, SelectorTier.key);
      expect(s.value, 'submit_btn');
    });

    test('parses text selector', () {
      final s = Selector.parse('text:Hello World');
      expect(s.tier, SelectorTier.text);
      expect(s.value, 'Hello World');
    });

    test('parses index selector', () {
      final s = Selector.parse('index:ElevatedButton:3');
      expect(s.tier, SelectorTier.byIndex);
      expect(s.value, 'ElevatedButton');
      expect(s.index, 3);
    });

    test('treats bare string as text selector', () {
      final s = Selector.parse('Submit');
      expect(s.tier, SelectorTier.text);
      expect(s.value, 'Submit');
    });

    test('treats unknown prefix as text selector', () {
      final s = Selector.parse('widget:MyWidget');
      expect(s.tier, SelectorTier.text);
      expect(s.value, 'widget:MyWidget');
    });

    test('rejects malformed index selector', () {
      expect(
        () => Selector.parse('index:Button'),
        throwsA(isA<FormatException>()),
      );
    });

    test('toString round-trips', () {
      expect(Selector.parse('semantics:Submit').toString(), 'semantics:Submit');
      expect(Selector.parse('key:btn').toString(), 'key:btn');
      expect(Selector.parse('index:Button:2').toString(), 'index:Button:2');
    });
  });
}
