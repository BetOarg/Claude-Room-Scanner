import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class SyncService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  /// Sincroniza un proyecto local hacia la nube
  Future<void> syncProjectToCloud({
    required String projectId,
    required String name,
    required Map<String, dynamic> projectData,
  }) async {
    final user = _authService.currentUser;
    if (user == null) return; // Si no hay usuario en sesión, se mantiene solo local

    try {
      await _supabase.from('projects').upsert({
        'id': projectId,
        'user_id': user.id,
        'name': name,
        'data': projectData,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Manejo de error de red / guardar en cola diferida
      rethrow;
    }
  }
}