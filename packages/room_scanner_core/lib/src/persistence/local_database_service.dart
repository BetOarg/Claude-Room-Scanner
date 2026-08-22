import 'package:isar/isar.dart';

import '../models/isar_models.dart';
import '../models/room_model.dart';

class LocalDatabaseService {
  late Isar _isar;

  /// Inicializa la base de datos Isar en el directorio indicado.
  ///
  /// `room_scanner_core` no depende de `path_provider` (es un plugin de
  /// Flutter con canal nativo): quien lo consuma —hoy `room_scanner_app`,
  /// vía `ProjectProvider.init()`— resuelve el directorio de documentos de
  /// la aplicación y lo pasa ya armado. Esto mantiene el paquete core como
  /// Dart puro, sin dependencias de plugins de Flutter.
  Future<void> init({required String directoryPath}) async {
    _isar = await Isar.open(
      [
        IsarProjectSchema,
        IsarRoomSchema,
      ],
      directory: directoryPath,
    );
  }

  /// Guarda o actualiza un proyecto completo.
  ///
  /// Las habitaciones anteriores del proyecto se eliminan antes
  /// de guardar la nueva versión. Esto evita que Isar acumule
  /// copias del mismo ambiente en cada persistencia.
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    final now = DateTime.now();

    final existingProject =
        await _isar.isarProjects
            .filter()
            .uuidEqualTo(uuid)
            .findFirst();

    final projectToSave =
        existingProject ??
            (IsarProject()
              ..uuid = uuid
              ..createdAt = now);

    projectToSave.name = name;
    projectToSave.updatedAt = now;

    final oldRoomDatabaseIds = <Id>[];

    if (existingProject != null) {
      // Es obligatorio cargar los enlaces antes de limpiarlos.
      // Si no se cargan, Isar puede conservar relaciones anteriores
      // y cada guardado termina agregando nuevas copias.
      await existingProject.rooms.load();

      oldRoomDatabaseIds.addAll(
        existingProject.rooms.map(
          (room) => room.id,
        ),
      );
    }

    final roomsToSave =
        rooms.map(
      (room) => room.toIsar(),
    ).toList();

    await _isar.writeTxn(() async {
      // Primero guardamos el proyecto para garantizar que tenga
      // un identificador válido.
      await _isar.isarProjects.put(
        projectToSave,
      );

      if (existingProject != null) {
        projectToSave.rooms.clear();

        await projectToSave.rooms.save();

        if (oldRoomDatabaseIds.isNotEmpty) {
          await _isar.isarRooms.deleteAll(
            oldRoomDatabaseIds,
          );
        }
      }

      if (roomsToSave.isNotEmpty) {
        await _isar.isarRooms.putAll(
          roomsToSave,
        );

        projectToSave.rooms.addAll(
          roomsToSave,
        );

        await projectToSave.rooms.save();
      }
    });
  }

  /// Obtiene todos los proyectos ordenados por fecha
  /// de actualización descendente.
  Future<List<IsarProject>>
      getAllProjects() async {
    return _isar.isarProjects
        .where()
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// Obtiene únicamente los ambientes vinculados
  /// al proyecto solicitado.
  Future<List<RoomModel>>
      getRoomsForProject(
    String uuid,
  ) async {
    final project =
        await _isar.isarProjects
            .filter()
            .uuidEqualTo(uuid)
            .findFirst();

    if (project == null) {
      return [];
    }

    await project.rooms.load();

    return project.rooms
        .map(
          (room) => room.toDomain(),
        )
        .toList();
  }

  /// Elimina un proyecto y todas las habitaciones
  /// que le pertenecen.
  Future<void> deleteProject(
    String uuid,
  ) async {
    final project =
        await _isar.isarProjects
            .filter()
            .uuidEqualTo(uuid)
            .findFirst();

    if (project == null) {
      return;
    }

    await project.rooms.load();

    final roomIds =
        project.rooms
            .map(
              (room) => room.id,
            )
            .toList();

    await _isar.writeTxn(() async {
      project.rooms.clear();

      await project.rooms.save();

      if (roomIds.isNotEmpty) {
        await _isar.isarRooms.deleteAll(
          roomIds,
        );
      }

      await _isar.isarProjects.delete(
        project.id,
      );
    });
  }
}