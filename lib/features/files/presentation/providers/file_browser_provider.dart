import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/sync/domain/index_sync_service.dart';

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return FileRepository(database: db);
});

class FileBrowserState {
  final String? currentFolderId;
  final List<FileNode> breadcrumbs;
  final List<FileNode> items;
  final bool isGridView;
  final Set<String> selectedIds;
  final bool isMultiSelect;
  final String? searchQuery;
  final String? filterMimePrefix;
  final bool isFavoritesOnly;
  final bool isLoading;

  const FileBrowserState({
    this.currentFolderId,
    this.breadcrumbs = const [],
    this.items = const [],
    this.isGridView = true,
    this.selectedIds = const {},
    this.isMultiSelect = false,
    this.searchQuery,
    this.filterMimePrefix,
    this.isFavoritesOnly = false,
    this.isLoading = false,
  });

  FileBrowserState copyWith({
    String? currentFolderId,
    bool clearFolder = false,
    List<FileNode>? breadcrumbs,
    List<FileNode>? items,
    bool? isGridView,
    Set<String>? selectedIds,
    bool? isMultiSelect,
    String? searchQuery,
    String? filterMimePrefix,
    bool clearFilters = false,
    bool? isFavoritesOnly,
    bool? isLoading,
  }) {
    return FileBrowserState(
      currentFolderId: clearFolder ? null : (currentFolderId ?? this.currentFolderId),
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      items: items ?? this.items,
      isGridView: isGridView ?? this.isGridView,
      selectedIds: selectedIds ?? this.selectedIds,
      isMultiSelect: isMultiSelect ?? this.isMultiSelect,
      searchQuery: clearFilters ? null : (searchQuery ?? this.searchQuery),
      filterMimePrefix: clearFilters ? null : (filterMimePrefix ?? this.filterMimePrefix),
      isFavoritesOnly: clearFilters ? false : (isFavoritesOnly ?? this.isFavoritesOnly),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FileBrowserNotifier extends StateNotifier<FileBrowserState> {
  final FileRepository _repository;
  final Ref _ref;

  FileBrowserNotifier({
    required FileRepository repository,
    required Ref ref,
  })  : _repository = repository,
        _ref = ref,
        super(const FileBrowserState(isLoading: true)) {
    loadCurrentFolder();
  }

  void _triggerAutoSync() {
    final masterKey = _ref.read(authNotifierProvider).masterKey;
    if (masterKey != null) {
      _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: masterKey);
    }
  }

  Future<void> loadCurrentFolder() async {
    state = state.copyWith(isLoading: true);

    List<FileNode> breadcrumbs = [];
    if (state.currentFolderId != null) {
      breadcrumbs = await _repository.getBreadcrumbs(state.currentFolderId!);
    }

    final items = await _repository.getNodes(
      parentId: state.currentFolderId,
      onlyFavorites: state.isFavoritesOnly,
      searchQuery: state.searchQuery,
      mimePrefix: state.filterMimePrefix,
    );

    state = state.copyWith(
      breadcrumbs: breadcrumbs,
      items: items,
      isLoading: false,
    );
  }

  void navigateToFolder(String? folderId) {
    state = state.copyWith(
      currentFolderId: folderId,
      clearFolder: folderId == null,
      selectedIds: {},
      isMultiSelect: false,
    );
    loadCurrentFolder();
  }

  void toggleViewMode() {
    state = state.copyWith(isGridView: !state.isGridView);
  }

  void toggleFavoritesFilter() {
    state = state.copyWith(
      isFavoritesOnly: !state.isFavoritesOnly,
    );
    loadCurrentFolder();
  }

  void setFilterMime(String? mimePrefix) {
    state = state.copyWith(filterMimePrefix: mimePrefix);
    loadCurrentFolder();
  }

  void setSearchQuery(String? query) {
    state = state.copyWith(searchQuery: query);
    loadCurrentFolder();
  }

  void toggleSelect(String nodeId) {
    final current = Set<String>.from(state.selectedIds);
    if (current.contains(nodeId)) {
      current.remove(nodeId);
    } else {
      current.add(nodeId);
    }

    state = state.copyWith(
      selectedIds: current,
      isMultiSelect: current.isNotEmpty,
    );
  }

  void selectAll() {
    final allIds = state.items.map((e) => e.id).toSet();
    state = state.copyWith(
      selectedIds: allIds,
      isMultiSelect: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      selectedIds: {},
      isMultiSelect: false,
    );
  }

  Future<void> createFolder(String name) async {
    await _repository.createFolder(
      name: name,
      parentId: state.currentFolderId,
    );
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> renameNode(String id, String newName) async {
    await _repository.renameNode(id, newName);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> moveNode(String id, String? targetFolderId) async {
    await _repository.moveNode(id, targetFolderId);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> toggleFavorite(String id, bool isFav) async {
    await _repository.toggleFavorite(id, isFav);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> moveToTrash(String id) async {
    await _repository.moveToTrash(id);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> deleteSelected() async {
    // BUG 11 FIX: Batch delete in a single database transaction
    final ids = state.selectedIds.toList();
    await _repository.trashNodes(ids);
    clearSelection();
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  /// Manually triggers immediate cloud backup
  Future<void> syncNow() async {
    final masterKey = _ref.read(authNotifierProvider).masterKey;
    if (masterKey != null) {
      await _ref.read(indexSyncServiceProvider).backupIndexToCloud(masterKey: masterKey);
    }
  }
}

final fileBrowserProvider =
    StateNotifierProvider<FileBrowserNotifier, FileBrowserState>((ref) {
  final repo = ref.watch(fileRepositoryProvider);
  return FileBrowserNotifier(repository: repo, ref: ref);
});
