import 'package:shared_preferences/shared_preferences.dart';

class RecentRoomNamesService {
  static const _storageKey = 'recent_room_names';
  static const _maximumNames = 6;

  final SharedPreferencesAsync _preferences;

  RecentRoomNamesService({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  Future<List<String>> load() async {
    return await _preferences.getStringList(_storageKey) ?? const [];
  }

  Future<void> remember(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;

    final current = await load();
    final updated = <String>[
      normalized,
      ...current.where(
        (item) => item.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(_maximumNames).toList();

    await _preferences.setStringList(_storageKey, updated);
  }
}