import 'package:dartnative/dartnative.dart';

import 'scribe.dart';
import 'transcript_screen.dart';

const Color _kCanvas = Color(0xFFF2F2F7);
const Color _kInk = Color(0xFF111111);
const Color _kMuted = Color(0xFF6B6B70);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ponytail: only handles transcribe-audio- and transcribe-openin- prefixes with 36-char UUIDs, support custom prefixes if Swift adds more derived stems
  static final _prefixRegExp = RegExp(r'^transcribe-(?:audio|openin)-.{36}-');

  String? _filePath;
  String? _fileName;
  bool _convertedFromVideo = false;
  bool _running = false;
  bool _cancelling = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    onOpenFile(_handlePickedFile);
  }

  void _handlePickedFile(String path) {
    if (!mounted || _running) return;
    final basename = path.split('/').last;
    final displayName = basename.replaceFirst(_prefixRegExp, '');
    setState(() {
      _filePath = path;
      _fileName = displayName;
      _convertedFromVideo = basename.startsWith('transcribe-audio-');
      _running = false;
      _cancelling = false;
      _progress = 0.0;
    });
  }

  Future<void> _pickAudio() async {
    try {
      final path = await pickAudio();
      if (path != null && mounted) {
        _handlePickedFile(path);
      }
    } catch (e) {
      if (mounted) {
        showAlert(context: context, title: 'Error', message: '$e');
      }
    }
  }

  Future<void> _onTranscribeTap() async {
    if (!hasApiKey()) {
      final saved = await _showApiKeySheet();
      if (!saved || !mounted) return;
    }
    _startTranscription();
  }

  Future<void> _startTranscription() async {
    if (_filePath == null) return;
    setState(() {
      _running = true;
      _cancelling = false;
      _progress = 0.0;
    });

    int lastPercent = 0;

    try {
      final result = await transcribe(
        _filePath!,
        onProgress: (p) {
          final percent = (p * 100).round();
          if (percent != lastPercent && mounted && _running) {
            lastPercent = percent;
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _cancelling = false;
      });
      Navigator.push(
        context,
        PageRoute(
          builder: (_) => TranscriptScreen(
            result: result,
            fileName: _fileName ?? 'Audio',
          ),
        ),
      );
    } on TranscribeCancelled {
      if (mounted) {
        setState(() {
          _running = false;
          _cancelling = false;
        });
      }
    } on TranscribeError catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _cancelling = false;
        });
        showAlert(context: context, title: 'Error', message: e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _cancelling = false;
        });
        showAlert(context: context, title: 'Error', message: '$e');
      }
    }
  }

  void _cancelTranscription() {
    if (_cancelling) return;
    cancel();
    setState(() => _cancelling = true);
  }

  Future<bool> _showApiKeySheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => const _ApiKeySheet(),
    );
    if (saved == true && mounted) {
      showToast(context, 'API key saved');
    }
    return saved ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCanvas,
      appBar: AppBar(
        title: const Text('Transcribe'),
        actions: [
          BarButtonItem(
            icon: 'key',
            fontIcon: CupertinoIcons.lock,
            onPressed: _showApiKeySheet,
          ),
        ],
      ),
      body: SafeArea(
        child: _running
            ? _buildRunningView()
            : _filePath != null
                ? _buildPickedView()
                : _buildIdleView(),
      ),
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Button(
              title: 'Choose Audio or Video',
              variant: ButtonVariant.filled,
              onPressed: _pickAudio,
            ),
            const SizedBox(height: 12),
            const Text(
              'Or share a recording to Transcribe from Voice Memos or Files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _fileName ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kInk,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_convertedFromVideo) ...[
              const SizedBox(height: 4),
              const Text(
                'Converted to M4A',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kMuted,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 28),
            Button(
              title: 'Transcribe',
              variant: ButtonVariant.filled,
              onPressed: _onTranscribeTap,
            ),
            const SizedBox(height: 8),
            Button(
              title: 'Choose another',
              variant: ButtonVariant.plain,
              onPressed: _pickAudio,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningView() {
    final String statusText;
    if (_cancelling) {
      statusText = 'Cancelling…';
    } else if (_progress < 1.0) {
      statusText = 'Uploading ${(_progress * 100).round()}%';
    } else {
      statusText = 'Transcribing…';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_fileName != null) ...[
              Text(
                _fileName!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
            ],
            LinearProgressIndicator(
              value: _progress < 1.0 ? _progress : null,
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            Button(
              title: 'Cancel',
              variant: ButtonVariant.bordered,
              onPressed: _cancelling ? null : _cancelTranscription,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiKeySheet extends StatefulWidget {
  const _ApiKeySheet();

  @override
  State<_ApiKeySheet> createState() => _ApiKeySheetState();
}

class _ApiKeySheetState extends State<_ApiKeySheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    try {
      setApiKey(key);
      Navigator.pop(context, true);
    } catch (e) {
      showAlert(context: context, title: 'Error', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            obscureText: true,
            clearButtonMode: ClearButtonMode.always,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'ElevenLabs API key',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Stored in the iOS Keychain on this device.',
            style: TextStyle(
              color: _kMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Button(
            title: 'Save',
            variant: ButtonVariant.filled,
            onPressed: _save,
          ),
          const SizedBox(height: 8),
          Button(
            title: 'Cancel',
            variant: ButtonVariant.plain,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}
