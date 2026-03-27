import 'package:flutter/material.dart';

/// Test fixture app for flutter_devtools_mcp.
///
/// Deliberately messy — exercises edge cases the MCP server must handle:
/// overlays, nested navigators, scrolling, mixed semantics, text input,
/// disabled widgets, animations.
void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Test Fixture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

/// Tab-based shell with multiple tabs to exercise different scenarios.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          WidgetGalleryTab(),
          ScrollTestTab(),
          FormTestTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.widgets),
            label: 'Widgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.list),
            label: 'Scroll',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit),
            label: 'Form',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 1: Widget Gallery
// ─────────────────────────────────────────────

class WidgetGalleryTab extends StatefulWidget {
  const WidgetGalleryTab({super.key});

  @override
  State<WidgetGalleryTab> createState() => _WidgetGalleryTabState();
}

class _WidgetGalleryTabState extends State<WidgetGalleryTab> {
  int _counter = 0;
  bool _switchValue = false;
  bool _checkboxValue = false;
  double _sliderValue = 0.5;
  String? _asyncData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Simulate async load (FutureBuilder scenario)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _asyncData = 'Loaded!';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget Gallery')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Semantics-labeled button
              Semantics(
                label: 'Increment',
                child: ElevatedButton(
                  key: const ValueKey('increment_btn'),
                  onPressed: () => setState(() => _counter++),
                  child: Text('Count: $_counter'),
                ),
              ),
              const SizedBox(height: 8),

              // Disabled button
              Semantics(
                label: 'Disabled Action',
                child: ElevatedButton(
                  onPressed: null,
                  child: const Text('Disabled'),
                ),
              ),
              const SizedBox(height: 8),

              // Duplicate labels (ambiguity test — 3 buttons same label)
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Semantics(
                    label: 'Action',
                    child: OutlinedButton(
                      onPressed: () {},
                      child: Text('Action $i'),
                    ),
                  ),
                ),

              const Divider(),

              // Switch
              SwitchListTile(
                key: const ValueKey('test_switch'),
                title: const Text('Toggle switch'),
                value: _switchValue,
                onChanged: (v) => setState(() => _switchValue = v),
              ),

              // Checkbox
              CheckboxListTile(
                key: const ValueKey('test_checkbox'),
                title: const Text('Check me'),
                value: _checkboxValue,
                onChanged: (v) => setState(() => _checkboxValue = v ?? false),
              ),

              // Slider
              Semantics(
                label: 'Volume',
                child: Slider(
                  key: const ValueKey('test_slider'),
                  value: _sliderValue,
                  onChanged: (v) => setState(() => _sliderValue = v),
                ),
              ),

              const Divider(),

              // Async state (FutureBuilder-like)
              if (_loading)
                const CircularProgressIndicator(
                  key: ValueKey('loading_indicator'),
                )
              else
                Text(
                  _asyncData ?? '',
                  key: const ValueKey('async_result'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

              const Divider(),

              // CustomPaint (no semantics, no text, no key — unaddressable)
              CustomPaint(
                size: const Size(100, 100),
                painter: _CirclePainter(),
              ),

              const SizedBox(height: 8),

              // Dialog trigger
              Semantics(
                label: 'Open Dialog',
                child: FilledButton(
                  onPressed: () => _showTestDialog(context),
                  child: const Text('Show Dialog'),
                ),
              ),

              const SizedBox(height: 8),

              // Bottom sheet trigger
              Semantics(
                label: 'Open Sheet',
                child: FilledButton.tonal(
                  onPressed: () => _showTestSheet(context),
                  child: const Text('Show Bottom Sheet'),
                ),
              ),

              const SizedBox(height: 8),

              // SnackBar trigger
              Semantics(
                label: 'Show Snack',
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Snackbar message'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Show SnackBar'),
                ),
              ),

              const SizedBox(height: 8),

              // Navigate to Hero page
              Semantics(
                label: 'Go Hero',
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HeroDetailPage(),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'hero-box',
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTestDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Dialog'),
        content: const Text('Dialog content here'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          Semantics(
            label: 'Confirm',
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  void _showTestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bottom Sheet Content'),
            const SizedBox(height: 16),
            Semantics(
              label: 'Close Sheet',
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      Paint()..color = Colors.teal,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
// Hero detail page (animation test)
// ─────────────────────────────────────────────

class HeroDetailPage extends StatelessWidget {
  const HeroDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hero Detail')),
      body: Center(
        child: Hero(
          tag: 'hero-box',
          child: Container(
            width: 200,
            height: 200,
            color: Colors.indigo,
            child: const Center(
              child: Text(
                'Hero',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 2: Scroll Test
// ─────────────────────────────────────────────

class ScrollTestTab extends StatelessWidget {
  const ScrollTestTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scroll Tests')),
      body: Column(
        children: [
          // Horizontal scroll inside vertical (nested scrollables)
          SizedBox(
            height: 120,
            child: ListView.builder(
              key: const ValueKey('horizontal_list'),
              scrollDirection: Axis.horizontal,
              itemCount: 20,
              itemBuilder: (ctx, i) => Container(
                width: 100,
                margin: const EdgeInsets.all(8),
                color: Colors.primaries[i % Colors.primaries.length],
                child: Center(
                  child: Semantics(
                    label: 'H-Item $i',
                    child: Text(
                      'H-$i',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(),
          // Vertical ListView.builder (500 items — lazy children test)
          Expanded(
            child: ListView.builder(
              key: const ValueKey('vertical_list'),
              itemCount: 500,
              itemBuilder: (ctx, i) => ListTile(
                key: ValueKey('item_$i'),
                leading: CircleAvatar(child: Text('$i')),
                title: Text('Item number $i'),
                subtitle: i % 10 == 0
                    ? Semantics(
                        label: 'Milestone $i',
                        child: Text('Milestone at $i'),
                      )
                    : null,
                onTap: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 3: Form Test
// ─────────────────────────────────────────────

class FormTestTab extends StatefulWidget {
  const FormTestTab({super.key});

  @override
  State<FormTestTab> createState() => _FormTestTabState();
}

class _FormTestTabState extends State<FormTestTab> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  String _submitted = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form Tests')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Text fields with keys and semantics
            Semantics(
              label: 'Name Field',
              child: TextField(
                key: const ValueKey('name_field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Semantics(
              label: 'Email Field',
              child: TextField(
                key: const ValueKey('email_field'),
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(height: 12),

            // Text field WITHOUT key or semantics (fallback test)
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Submit button
            Semantics(
              label: 'Submit Form',
              child: FilledButton(
                key: const ValueKey('submit_btn'),
                onPressed: () {
                  setState(() {
                    _submitted =
                        '${_nameController.text} | ${_emailController.text}';
                  });
                },
                child: const Text('Submit'),
              ),
            ),
            const SizedBox(height: 16),

            // Result display
            if (_submitted.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Submitted: $_submitted',
                    key: const ValueKey('submit_result'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
