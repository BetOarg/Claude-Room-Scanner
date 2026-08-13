import 'package:flutter/foundation.dart';
import '../models/isar_models.dart';
import '../models/room_model.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';

class ProjectProvider with ChangeNotifier {
  final LocalDatabaseService _dbService = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<IsarProject> _projects = [];
  IsarProject? _currentProject;
  bool _isLoading = false;

  List<IsarProject> get projects => _projects;
  IsarProject? get currentProject => _currentProject;
  bool get isLoading => _isLoading;

  /// Inicializa la base de datos y carga los proyectos guardados
  Future<void> init() async {
    _setLoading(true);
    await _dbService.init();
    await loadProjects();
    _setLoading(false);
  }

  /// Carga la lista de proyectos desde Isar
  Future<void> loadProjects() async {
    _projects = await _dbService.getAllProjects();
    notifyListeners();
  }

  /// Crea o guarda un proyecto existente (Persistencia Isar DB + Nube Supabase)
  Future<void> saveCurrentProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    _setLoading(true);

    // 1. Guardado en base de datos local (Isar DB)
    await _dbService.saveProject(
      uuid: uuid,
      name: name,
      rooms: rooms,
    );

    // 2. Sincronización en segundo plano con Supabase
    try {
      final roomsData = rooms.map((room) => room.toJson()).toList();
      await _syncService.syncProjectToCloud(
        projectId: uuid,
        name: name,
        projectData: {'rooms': roomsData},
      );
    } catch (e) {
      // Si no hay conexión o falla la nube, la información ya quedó segura en Isar
      debugPrint('Sincronización en la nube en espera/fallida: $e');
    }

    await loadProjects();
    _setLoading(false);
  }

  /// Carga un proyecto para trabajar en él
  Future<List<RoomModel>> selectProject(IsarProject project) async {
    _currentProject = project;
    notifyListeners();
    return await _dbService.getRoomsForProject(project.uuid);
  }

  /// Elimina un proyecto por su UUID
  Future<void> deleteProject(String uuid) async {
    _setLoading(true);
    await _dbService.deleteProject(uuid);
    if (_currentProject?.uuid == uuid) {
      _currentProject = null;
    }
    await loadProjects();
    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}