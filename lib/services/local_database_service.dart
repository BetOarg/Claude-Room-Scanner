import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_models.dart';
import '../models/room_model.dart';

class LocalDatabaseService {
  late Isar _isar;

  /// Inicializa la base de datos Isar en el directorio de documentos
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [IsarProjectSchema, IsarRoomSchema],
      directory: dir.path,
    );
  }

  /// Guarda o actualiza un proyecto completo con sus habitaciones
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    final now = DateTime.now();

    // Busca si el proyecto ya existe por su UUID
    IsarProject? existingProject =
        await _isar.isarProjects.filter().uuidEqualTo(uuid).findFirst();

    final projectToSave = existingProject ?? IsarProject()
      ..uuid = uuid
      ..createdAt = now;

    projectToSave.name = name;
    projectToSave.updatedAt = now;

    final isarRooms = rooms.map((r) => r.toIsar()).toList();

    await _isar.writeTxn(() async {
      await _isar.isarRooms.putAll(isarRooms);
      await _isar.isarProjects.put(projectToSave);

      projectToSave.rooms.clear();
      projectToSave.rooms.addAll(isarRooms);
      await projectToSave.rooms.save();
    });
  }

  /// Obtiene todos los proyectos ordenados por la última actualización
  Future<List<IsarProject>> getAllProjects() async {
    return await _isar.isarProjects.where().sortByUpdatedAtDesc().findAll();
  }

  /// Obtiene las habitaciones asociadas a un proyecto
  Future<List<RoomModel>> getRoomsForProject(String uuid) async {
    final project =
        await _isar.isarProjects.filter().uuidEqualTo(uuid).findFirst();
    if (project == null) return [];

    await project.rooms.load();
    return project.rooms.map((r) => r.toDomain()).toList();
  }

  /// Elimina un proyecto y sus habitaciones relacionadas
  Future<void> deleteProject(String uuid) async {
    final project =
        await _isar.isarProjects.filter().uuidEqualTo(uuid).findFirst();
    if (project == null) return;

    await _isar.writeTxn(() async {
      await project.rooms.load();
      final roomIds = project.rooms.map((r) => r.id).toList();

      await _isar.isarRooms.deleteAll(roomIds);
      await _isar.isarProjects.delete(project.id);
    });
  }
}