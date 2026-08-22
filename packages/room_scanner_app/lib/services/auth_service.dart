import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene el usuario autenticado actualmente
  User? get currentUser => _supabase.auth.currentUser;

  /// Escucha los cambios de estado de autenticación
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Registro con email y contraseña
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Inicio de sesión con email y contraseña
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Cerrar sesión
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}