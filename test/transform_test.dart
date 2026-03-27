import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/transform.dart';

void main() {
  group('transformTree', () {
    test('extracts id and type from raw node', () {
      final result = transformTree({
        'valueId': 'inspector-0x123',
        'description': 'ElevatedButton',
        'children': <Object?>[],
      });
      expect(result['id'], 'inspector-0x123');
      expect(result['type'], 'ElevatedButton');
    });

    test('falls back to objectId when valueId missing', () {
      final result = transformTree({
        'objectId': 'objects/42',
        'description': 'Text',
      });
      expect(result['id'], 'objects/42');
    });

    test('extracts key from properties', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'Container',
        'properties': <Object?>[
          <String, Object?>{'name': 'key', 'description': 'my_key'},
        ],
      });
      expect(result['key'], 'my_key');
    });

    test('extracts label from properties', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'Semantics',
        'properties': <Object?>[
          <String, Object?>{'name': 'label', 'description': 'Submit'},
        ],
      });
      expect(result['label'], 'Submit');
    });

    test('extracts text data from properties', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'Text',
        'properties': <Object?>[
          <String, Object?>{'name': 'data', 'description': 'Hello'},
        ],
      });
      expect(result['text'], 'Hello');
    });

    test('detects disabled state from onPressed=null', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'ElevatedButton',
        'properties': <Object?>[
          <String, Object?>{'name': 'onPressed', 'description': 'null'},
        ],
      });
      expect(result['enabled'], false);
    });

    test('recurses children', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'Column',
        'children': <Object?>[
          <String, Object?>{
            'valueId': 'v2',
            'description': 'Text',
            'properties': <Object?>[
              <String, Object?>{'name': 'data', 'description': 'Hello'},
            ],
          },
        ],
      });
      final children = result['children'] as List;
      expect(children, hasLength(1));
      expect((children[0] as Map)['type'], 'Text');
    });

    test('marks inScrollable for ListView children', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'ListView',
        'children': <Object?>[
          <String, Object?>{
            'valueId': 'v2',
            'description': 'ListTile',
          },
        ],
      });
      expect(result['inScrollable'], true);
      final children = result['children'] as List;
      expect((children[0] as Map)['inScrollable'], true);
    });

    test('extracts bounds from renderObject', () {
      final result = transformTree({
        'valueId': 'v1',
        'description': 'Container',
        'renderObject': <String, Object?>{
          'properties': <Object?>[
            <String, Object?>{
              'name': 'size',
              'description': 'Size(200.0, 48.0)',
            },
            <String, Object?>{
              'name': 'paintBounds',
              'description': 'Rect.fromLTWH(10.0, 20.0, 200.0, 48.0)',
            },
          ],
        },
      });
      expect(result['bounds'], isNotNull);
      final bounds = result['bounds'] as Map<String, Object?>;
      expect(bounds['w'], 200.0);
      expect(bounds['h'], 48.0);
      expect(result['visible'], true);
    });
  });

  group('flattenTree', () {
    test('flattens nested tree depth-first', () {
      final tree = transformTree({
        'valueId': 'v1',
        'description': 'Column',
        'children': <Object?>[
          <String, Object?>{'valueId': 'v2', 'description': 'Text'},
          <String, Object?>{'valueId': 'v3', 'description': 'Button'},
        ],
      });
      final flat = flattenTree(tree);
      expect(flat, hasLength(3));
      expect(flat[0]['type'], 'Column');
      expect(flat[1]['type'], 'Text');
      expect(flat[2]['type'], 'Button');
      // Flattened nodes should not have children key
      expect(flat[0].containsKey('children'), false);
    });
  });
}
