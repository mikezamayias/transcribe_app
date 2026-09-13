import 'package:dartnative/dartnative.dart';
import 'package:dartnative_share/dartnative_share.dart';

import 'theme.dart';
import 'transcript_model.dart';

const List<Color> _kSpeakerPalette = [
  Color(0xFF007AFF), // system blue
  Color(0xFF34C759), // system green
  Color(0xFFFF9500), // system orange
  Color(0xFFAF52DE), // system purple
];

class TranscriptScreen extends StatelessWidget {
  const TranscriptScreen({
    super.key,
    required this.result,
    required this.fileName,
  });

  final TranscriptResult result;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          BarButtonItem(
            icon: 'square.and.arrow.up',
            fontIcon: CupertinoIcons.square_arrow_up,
            onPressed: () {
              Share.share(result.plainText);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                _formatMeta(result),
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: result.turns.isEmpty
                  ? Center(
                      child: Text(
                        'No speech detected.',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: result.turns.length,
                      itemBuilder: (context, index) {
                        final turn = result.turns[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == result.turns.length - 1 ? 0 : 12,
                          ),
                          child: _SpeakerTurnRow(turn: turn),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMeta(TranscriptResult result) {
    final lang = result.language.isEmpty ? '?' : result.language.toUpperCase();
    final prob = '${(result.probability * 100).round()}%';
    final speakers =
        '${result.speakerCount} ${result.speakerCount == 1 ? 'speaker' : 'speakers'}';
    final dur = _formatDuration(result.duration);
    return '$lang · $prob · $speakers · $dur';
  }

  static String _formatDuration(double seconds) {
    final total = seconds.floor().clamp(0, 1 << 30);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:${two(m)}:${two(s)}';
    }
    return '${two(m)}:${two(s)}';
  }
}

class _SpeakerTurnRow extends StatelessWidget {
  const _SpeakerTurnRow({required this.turn});

  final SpeakerTurn turn;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final paletteIndex = turn.index >= 0 ? (turn.index % 4) : 0;
    final speakerNumber = turn.index >= 0 ? '${turn.index + 1}' : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _kSpeakerPalette[paletteIndex],
                shape: BoxShape.circle,
              ),
              child: Text(
                speakerNumber,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                turn.displayName,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              turn.timestamp,
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          turn.text,
          style: TextStyle(
            color: palette.ink,
            fontSize: 17,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
