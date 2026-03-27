import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/selectors.dart';

// These tests verify selector matching against mock widget tree data.
// They use the internal walkTree behavior indirectly by importing the library
// and testing the publicly visible Selector + ResolvedNode classes,
// plus the SelectorError behavior.

void main() {
  group('ResolvedNode', () {
    test('toJson includes all non-null fields', () {
      final node = ResolvedNode(
        id: 'v1',
        type: 'ElevatedButton',
        label: 'Submit',
        key: 'submit_btn',
        text: null,
        matchedVia: SelectorTier.semantics,
      );
      final json = node.toJson();
      expect(json['id'], 'v1');
      expect(json['type'], 'ElevatedButton');
      expect(json['label'], 'Submit');
      expect(json['key'], 'submit_btn');
      expect(json.containsKey('text'), false);
      expect(json['matchedVia'], 'semantics');
    });

    test('toJson omits null fields', () {
      final node = ResolvedNode(
        id: 'v2',
        type: 'Container',
        matchedVia: SelectorTier.byIndex,
      );
      final json = node.toJson();
      expect(json.containsKey('label'), false);
      expect(json.containsKey('key'), false);
      expect(json.containsKey('text'), false);
    });
  });

  group('SelectorError', () {
    test('toString includes message and match count', () {
      final err = SelectorError('Ambiguous', matchCount: 3);
      expect(err.toString(), contains('Ambiguous'));
      expect(err.toString(), contains('3'));
    });

    test('holds match list for diagnostics', () {
      final matches = [
        ResolvedNode(id: 'v1', type: 'Button', matchedVia: SelectorTier.text),
        ResolvedNode(id: 'v2', type: 'Button', matchedVia: SelectorTier.text),
      ];
      final err = SelectorError('Two matches', matchCount: 2, matches: matches);
      expect(err.matches, hasLength(2));
    });
  });

  group('Selector edge cases', () {
    test('semantics selector with colon in value', () {
      // "semantics:Time: 3:00 PM" — first colon is the tier separator
      final s = Selector.parse('semantics:Time: 3:00 PM');
      expect(s.tier, SelectorTier.semantics);
      expect(s.value, 'Time: 3:00 PM');
    });

    test('key selector with special characters', () {
      final s = Selector.parse('key:my-widget_v2.0');
      expect(s.tier, SelectorTier.key);
      expect(s.value, 'my-widget_v2.0');
    });

    test('index selector with zero', () {
      final s = Selector.parse('index:Text:0');
      expect(s.tier, SelectorTier.byIndex);
      expect(s.value, 'Text');
      expect(s.index, 0);
    });

    test('index selector rejects non-numeric index', () {
      expect(
        () => Selector.parse('index:Button:abc'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
