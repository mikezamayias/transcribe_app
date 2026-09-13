import 'dart:convert';

/// One contiguous speaker turn. Mirrors the JSON from `transcribe_start`.
class SpeakerTurn {
  const SpeakerTurn({
    required this.speaker,
    required this.start,
    required this.end,
    required this.text,
  });

  final String speaker;
  final double start;
  final double end;
  final String text;

  /// "speaker_0" -> 0. Non-matching ids -> -1.
  int get index =>
      speaker.startsWith('speaker_') ? (int.tryParse(speaker.substring(8)) ?? -1) : -1;

  String get displayName => index >= 0 ? 'Speaker ${index + 1}' : speaker;

  String get timestamp {
    final total = start.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  String get line => '[$timestamp] $displayName: ${text.trim()}';

  static SpeakerTurn fromJson(Map<String, dynamic> j) => SpeakerTurn(
        speaker: j['speaker'] as String? ?? 'unknown',
        start: (j['start'] as num?)?.toDouble() ?? 0,
        end: (j['end'] as num?)?.toDouble() ?? 0,
        text: j['text'] as String? ?? '',
      );
}

/// Successful result of `transcribe_start`.
class TranscriptResult {
  const TranscriptResult({
    required this.turns,
    required this.language,
    required this.probability,
    required this.duration,
  });

  final List<SpeakerTurn> turns;
  final String language;
  final double probability;
  final double duration;

  int get speakerCount => turns.map((t) => t.speaker).toSet().length;

  String get plainText => turns.map((t) => t.line).join('\n\n');

  static TranscriptResult fromJson(Map<String, dynamic> j) => TranscriptResult(
        turns: ((j['turns'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => SpeakerTurn.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        language: j['language'] as String? ?? '?',
        probability: (j['probability'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
      );

  static TranscriptResult decode(String json) =>
      fromJson(jsonDecode(json) as Map<String, dynamic>);
}
