/// Configuración de Supabase.
///
/// Las claves NO deben quedar hardcodeadas en el código fuente (ni siquiera
/// la anon key, que si bien es pública, conviene poder rotar por entorno sin
/// tocar código). Se leen en tiempo de compilación con `--dart-define`, por
/// ejemplo:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=tu-anon-key-real
///
/// Si no se pasan, se usan los valores de placeholder de abajo (la app sigue
/// arrancando, pero cualquier llamada a Supabase fallará hasta configurar
/// las claves reales).
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tu-proyecto.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'tu-anon-key-aqui',
  );
}
