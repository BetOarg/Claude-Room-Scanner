import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/isar_models.dart';
import '../providers/project_provider.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/auth_service.dart';
import '../services/ar_check_service.dart';
import 'floor_plan_viewer_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends State<DashboardScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      context
          .read<ProjectProvider>()
          .init();
    });
  }

  void _showNewProjectDialog(
    BuildContext context,
  ) {
    final controller =
        TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Nuevo Proyecto',
        ),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(
            hintText:
                'Ej: Remodelación Oficina',
            border:
                OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx),
            child:
                const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () =>
                _createProject(
              ctx,
              controller.text.trim(),
            ),
            child:
                const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(
    BuildContext dialogContext,
    String name,
  ) async {
    if (name.isEmpty) {
      return;
    }

    Navigator.pop(dialogContext);

    final uuid = DateTime.now()
        .millisecondsSinceEpoch
        .toString();

    await context
        .read<ProjectProvider>()
        .saveCurrentProject(
          uuid: uuid,
          name: name,
          rooms: const [],
        );

    if (!mounted) {
      return;
    }

    context
        .read<FloorPlanProvider>()
        .loadProject(
          uuid: uuid,
          name: name,
          rooms: const [],
        );

    context
        .read<ScannerProvider>()
        .loadRooms(const []);

    await ArCheckService
        .abrirEscanerConValidacion(
      context,
      projectUuid: uuid,
      projectName: name,
    );
  }

  Future<void> _openProject(
    IsarProject project,
  ) async {
    final provider =
        context.read<ProjectProvider>();

    final rooms =
        await provider.selectProject(
      project,
    );

    if (!mounted) {
      return;
    }

    context
        .read<FloorPlanProvider>()
        .loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );

    context
        .read<ScannerProvider>()
        .loadRooms(rooms);

    await ArCheckService
        .abrirEscanerConValidacion(
      context,
      projectUuid: project.uuid,
      projectName: project.name,
    );
  }

  Future<void> _viewFloorPlan(
    IsarProject project,
  ) async {
    final provider =
        context.read<ProjectProvider>();

    final rooms =
        await provider.selectProject(
      project,
    );

    if (!mounted) {
      return;
    }

    context
        .read<FloorPlanProvider>()
        .loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const FloorPlanViewerScreen(),
      ),
    );
  }

  void _handleSignOut() async {
    await _authService.signOut();

    if (mounted) {
      Navigator.of(context)
          .pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider =
        context.watch<ProjectProvider>();

    final user =
        _authService.currentUser;

    final theme =
        Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Proyectos AR',
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
            ),
            tooltip:
                'Cerrar Sesión',
            onPressed:
                _handleSignOut,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            color: theme
                .colorScheme
                .surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  user != null
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  color: user != null
                      ? Colors.green
                      : Colors.orangeAccent,
                  size: 20,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    user != null
                        ? 'Sincronizado: ${user.email}'
                        : 'Modo Offline '
                          '(Proyectos guardados localmente)',
                    style:
                        const TextStyle(
                      fontSize: 13,
                    ),
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: provider.isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : provider.projects.isEmpty
                    ? _buildEmptyState()
                    : _buildProjectList(
                        provider,
                      ),
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () =>
            _showNewProjectDialog(
          context,
        ),
        icon:
            const Icon(Icons.add),
        label: const Text(
          'Nuevo Escaneo',
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.architecture_rounded,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            'No tienes proyectos guardados',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          const Text(
            'Presiona "Nuevo Escaneo" '
            'para comenzar',
          ),
        ],
      ),
    );
  }

  Widget _buildProjectList(
    ProjectProvider provider,
  ) {
    return ListView.builder(
      padding:
          const EdgeInsets.all(16),
      itemCount:
          provider.projects.length,
      itemBuilder:
          (context, index) {
        final project =
            provider.projects[index];

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 12,
          ),
          child: ListTile(
            leading:
                const CircleAvatar(
              child: Icon(
                Icons.meeting_room,
              ),
            ),
            title: Text(
              project.name,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Actualizado: '
              '${project.updatedAt.day}/'
              '${project.updatedAt.month}/'
              '${project.updatedAt.year}',
            ),
            trailing: Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.map_outlined,
                  ),
                  tooltip:
                      'Ver plano',
                  onPressed: () =>
                      _viewFloorPlan(
                    project,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  tooltip:
                      'Eliminar',
                  onPressed: () async {
                    await provider
                        .deleteProject(
                      project.uuid,
                    );
                  },
                ),
              ],
            ),
            onTap: () =>
                _openProject(
              project,
            ),
          ),
        );
      },
    );
  }
}