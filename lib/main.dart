import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/room_model.dart';
import 'providers/scanner_provider.dart';
import 'providers/floor_plan_provider.dart';
import 'providers/project_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => ScannerProvider()),
        // FloorPlanProvider es el estado en memoria del proyecto abierto;
        // se conecta aquí a ProjectProvider (Isar) como su única vía de
        // persistencia durable, en vez de guardar por su cuenta en un
        // archivo aparte como hacía antes.
        ChangeNotifierProxyProvider<ProjectProvider, FloorPlanProvider>(
          create: (_) => FloorPlanProvider(),
          update: (_, projectProvider, floorPlanProvider) {
            final provider = floorPlanProvider ?? FloorPlanProvider();
            provider.persister = ({
              required String uuid,
              required String name,
              required List<RoomModel> rooms,
            }) =>
                projectProvider.saveCurrentProject(uuid: uuid, name: name, rooms: rooms);
            return provider;
          },
        ),
      ],
      child: RoomScannerApp(),
    ),
  );
}

class RoomScannerApp extends StatelessWidget {
  RoomScannerApp({super.key});

  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales:
          AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Escucha reactivamente si el usuario está autenticado o no
      home: StreamBuilder<AuthState>(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          final session = _authService.currentUser;
          
          if (session != null) {
            return const DashboardScreen();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}