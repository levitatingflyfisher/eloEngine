import 'dart:math';
import 'models.dart';

/// Sync mode for an [EloSession].
///
/// Only [SyncMode.standalone] is implemented in v1. v2 will add
/// [SyncMode.asyncMerge] for share-by-code merging across devices and
/// [SyncMode.liveSession] for realtime multi-participant voting.
enum SyncMode {
  /// Single device, single participant. The only mode supported in v1.
  standalone,

  /// v2 placeholder: share-by-code merge across devices.
  asyncMerge,

  /// v2 placeholder: realtime multi-participant voting.
  liveSession,
}

/// Snapshot of one participant's pairwise comparison state.
///
/// In v1 (Ghost mode), an [EloSession] is the input format for
/// [EloMerge.combine] — multiple participants share a single device, each
/// builds up a ranking via their own [EloEngine], snapshots are taken with
/// [EloEngine.snapshot], and the snapshots are combined.
///
/// v1 ignores the sync fields ([sessionCode], [hostParticipantId],
/// [expiresAt]); they are present in the schema so v2 can use the same
/// persisted format without a migration.
class EloSession {
  /// Stable identifier for this session. Auto-generated if not provided to
  /// the constructor.
  final String sessionId;

  /// Optional human-readable participant identifier (e.g. "alice", "bob").
  final String? participantId;

  /// Sync mode. v1 only supports [SyncMode.standalone].
  final SyncMode syncMode;

  /// Items as seen by this participant. Sort by [EloItem.rating] descending
  /// to recover this participant's ranking.
  final List<EloItem> items;

  /// Match history that produced [items]'s ratings.
  final List<EloMatch> history;

  // ── v2 sync fields (always null in v1 standalone mode) ─────────────────────
  /// Share-by-code join token. v2 only; always `null` in v1.
  final String? sessionCode;

  /// ID of the participant who created the session. v2 only; always `null` in v1.
  final String? hostParticipantId;

  /// Expiration wall-clock time. v2 only; always `null` in v1.
  final DateTime? expiresAt;

  /// Constructs a session. [sessionId] is auto-generated if omitted.
  EloSession({
    String? sessionId,
    this.participantId,
    this.syncMode = SyncMode.standalone,
    required this.items,
    required this.history,
    this.sessionCode,
    this.hostParticipantId,
    this.expiresAt,
  }) : sessionId = sessionId ?? _generateSessionId();

  static final _random = Random();

  static String _generateSessionId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(1 << 32).toRadixString(36);
    return 'session_${ms}_$rand';
  }

  /// Serializes to a JSON-compatible map. Round-trips via [EloSession.fromJson].
  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        if (participantId != null) 'participantId': participantId,
        'syncMode': syncMode.name,
        'items': items.map((i) => i.toJson()).toList(),
        'history': history.map((m) => m.toJson()).toList(),
        if (sessionCode != null) 'sessionCode': sessionCode,
        if (hostParticipantId != null) 'hostParticipantId': hostParticipantId,
        if (expiresAt != null)
          'expiresAt': expiresAt!.millisecondsSinceEpoch ~/ 1000,
      };

  /// Restores a session from its [toJson] representation.
  factory EloSession.fromJson(Map<String, dynamic> j) => EloSession(
        sessionId: j['sessionId'] as String,
        participantId: j['participantId'] as String?,
        syncMode:
            SyncMode.values.byName(j['syncMode'] as String? ?? 'standalone'),
        items: (j['items'] as List<dynamic>)
            .map((i) => EloItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        history: (j['history'] as List<dynamic>)
            .map((m) => EloMatch.fromJson(m as Map<String, dynamic>))
            .toList(),
        sessionCode: j['sessionCode'] as String?,
        hostParticipantId: j['hostParticipantId'] as String?,
        expiresAt: j['expiresAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as int) * 1000)
            : null,
      );
}
