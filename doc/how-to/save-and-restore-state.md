# How-to — save and restore state

```dart
import 'dart:convert';
import 'dart:io';
import 'package:elo_engine/elo_engine.dart';

// Persist
void save(EloEngine engine, String path) {
  File(path).writeAsStringSync(jsonEncode(engine.toJson()));
}

// Restore
EloEngine load(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return EloEngine.fromJson(json);
}
```

The serialised map includes `"version": 1`, the full match history, all
item ratings, and Glicko-2 and TrueSkill state snapshots. When you call
`fromJson` without `skipReplay: true`, the stored ratings are ignored and
recalculated from history — this guarantees correctness even if the
stored ratings are stale. The `skipReplay: true` path restores Glicko-2
and TrueSkill states from the snapshot only when all item IDs are
present; if any are missing the algorithm states are left at their
initial values rather than silently producing wrong results.
