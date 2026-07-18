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

  group('SelectorError', () {
    test('includes index hints in error message', () {
      final error = SelectorError(
        'Ambiguous: 2 nodes match "text:Connect".',
        matchCount: 2,
        matches: [
          ResolvedNode(
            id: 'node-1',
            type: 'Text',
            text: 'Connect',
            matchedVia: SelectorTier.text,
          ),
          ResolvedNode(
            id: 'node-2',
            type: 'Text',
            text: 'Connect',
            matchedVia: SelectorTier.text,
          ),
        ],
      );
      final msg = error.toString();
      expect(msg, contains('index:Text:0'));
      expect(msg, contains('index:Text:1'));
      expect(msg, contains('[0] Text'));
      expect(msg, contains('[1] Text'));
    });

    test('empty matches still shows count', () {
      final error = SelectorError('No match', matchCount: 0);
      final msg = error.toString();
      expect(msg, contains('No match'));
      expect(msg, contains('0'));
    });
  });
}
