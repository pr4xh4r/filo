import 'dart:typed_data';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/domain/storage_backend.dart';
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
  final String activeWorkspaceId;
  final List<Workspace> workspaces;
  final String? selectedTagId;
  final String? selectedCategory;

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
    this.activeWorkspaceId = 'personal',
    this.workspaces = Workspace.defaults,
    this.selectedTagId,
    this.selectedCategory,
  });

  /// Items filtered by active category (Photos, Videos, Docs, Audio, Folders)
  List<FileNode> get displayItems {
    if (selectedCategory == null) return items;
    switch (selectedCategory) {
      case 'photos':
        return items.where((i) => !i.isFolder && ((i.mimeType?.startsWith('image/') ?? false) || i.name.toLowerCase().endsWith('.jpg') || i.name.toLowerCase().endsWith('.png') || i.name.toLowerCase().endsWith('.jpeg') || i.name.toLowerCase().endsWith('.webp') || i.name.toLowerCase().endsWith('.heic'))).toList();
      case 'videos':
        return items.where((i) => !i.isFolder && ((i.mimeType?.startsWith('video/') ?? false) || i.name.toLowerCase().endsWith('.mp4') || i.name.toLowerCase().endsWith('.mov') || i.name.toLowerCase().endsWith('.mkv'))).toList();
      case 'docs':
        return items.where((i) => !i.isFolder && ((i.mimeType?.contains('pdf') ?? false) || (i.mimeType?.contains('document') ?? false) || (i.mimeType?.contains('text') ?? false) || i.name.toLowerCase().endsWith('.pdf') || i.name.toLowerCase().endsWith('.txt') || i.name.toLowerCase().endsWith('.docx') || i.name.toLowerCase().endsWith('.xlsx'))).toList();
      case 'audio':
        return items.where((i) => !i.isFolder && ((i.mimeType?.startsWith('audio/') ?? false) || i.name.toLowerCase().endsWith('.mp3') || i.name.toLowerCase().endsWith('.m4a') || i.name.toLowerCase().endsWith('.flac') || i.name.toLowerCase().endsWith('.wav'))).toList();
      case 'folders':
        return items.where((i) => i.isFolder).toList();
      default:
        return items;
    }
  }

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
    String? activeWorkspaceId,
    List<Workspace>? workspaces,
    String? selectedTagId,
    bool clearTag = false,
    String? selectedCategory,
    bool clearCategory = false,
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
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      workspaces: workspaces ?? this.workspaces,
      selectedTagId: clearTag ? null : (clearFilters ? null : (selectedTagId ?? this.selectedTagId)),
      selectedCategory: clearCategory ? null : (clearFilters ? null : (selectedCategory ?? this.selectedCategory)),
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
    _init();
  }

  Future<void> _init() async {
    await loadWorkspaces();
    await loadCurrentFolder();
  }

  Future<void> loadWorkspaces() async {
    try {
      final ws = await _repository.getWorkspaces();
      if (ws.isNotEmpty) {
        state = state.copyWith(workspaces: ws);
      }
    } catch (_) {}
  }

  Future<void> addWorkspace(String name, {bool isEncrypted = true}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final wsId = cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final newWs = Workspace(
      id: wsId,
      name: cleanName,
      description: isEncrypted ? 'Encrypted space' : 'Viewable space',
      icon: isEncrypted ? Icons.visibility_off_rounded : Icons.visibility_rounded,
      isEncrypted: isEncrypted,
    );
    try {
      await _repository.createWorkspace(newWs);
    } catch (_) {}

    final updated = [
      ...state.workspaces.where((w) => w.id != wsId),
      newWs,
    ];
    state = state.copyWith(
      workspaces: updated,
      activeWorkspaceId: wsId,
      clearFolder: true,
      selectedIds: {},
      isMultiSelect: false,
    );
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> removeWorkspace(String id) async {
    final fallbackId = (state.activeWorkspaceId == id) ? 'personal' : state.activeWorkspaceId;

    try {
      await _repository.deleteWorkspace(id, moveToTrash: true);
    } catch (_) {}

    await loadWorkspaces();

    state = state.copyWith(
      activeWorkspaceId: fallbackId,
      clearFolder: true,
      selectedIds: {},
      isMultiSelect: false,
    );
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> restoreWorkspace(String id) async {
    try {
      await _repository.restoreWorkspace(id);
    } catch (_) {}

    await loadWorkspaces();
    await loadCurrentFolder();
    _triggerAutoSync();
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
      workspaceId: state.currentFolderId == null ? state.activeWorkspaceId : null,
      tag: state.selectedTagId,
    );

    state = state.copyWith(
      breadcrumbs: breadcrumbs,
      items: items,
      isLoading: false,
    );
  }

  void setActiveWorkspace(String workspaceId) {
    if (state.activeWorkspaceId == workspaceId) return;
    state = state.copyWith(
      activeWorkspaceId: workspaceId,
      clearFolder: true,
      clearCategory: true,
      selectedIds: {},
      isMultiSelect: false,
    );
    loadCurrentFolder();
  }

  void setSelectedCategory(String? category) {
    if (category == null || category.isEmpty || state.selectedCategory == category) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategory: category);
    }
  }

  void setSelectedTag(String? tagId) {
    if (tagId == null || tagId.isEmpty) {
      // Explicitly clearing tag (e.g. tapping "All")
      state = state.copyWith(clearTag: true);
    } else if (state.selectedTagId == tagId) {
      // Toggle off if tapping already selected tag
      state = state.copyWith(clearTag: true);
    } else {
      state = state.copyWith(selectedTagId: tagId);
    }
    loadCurrentFolder();
  }

  void navigateToFolder(String? folderId) {
    state = state.copyWith(
      currentFolderId: folderId,
      clearFolder: folderId == null,
      clearCategory: true,
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

  Future<void> createFolder(String name, {List<String>? tags}) async {
    await _repository.createFolder(
      name: name,
      parentId: state.currentFolderId,
      workspaceId: state.activeWorkspaceId,
      tags: tags ?? (state.selectedTagId != null ? [state.selectedTagId!] : const []),
    );
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> updateNodeTags(String id, List<String> tags) async {
    await _repository.updateNodeTags(id, tags);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> updateNodeWorkspace(String id, String workspaceId) async {
    await _repository.updateNodeWorkspace(id, workspaceId);
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

  Future<bool> togglePinOffline(FileNode node, {Uint8List? masterKey, StorageBackend? storage}) async {
    final isPinned = await _repository.togglePinOffline(node, masterKey: masterKey, storage: storage);
    await loadCurrentFolder();
    return isPinned;
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

  Future<void> restoreFromTrash(String id) async {
    await _repository.restoreFromTrash(id);
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> emptyTrash() async {
    await _repository.emptyTrash();
    await loadWorkspaces();
    await loadCurrentFolder();
    _triggerAutoSync();
  }

  Future<void> reloadAll() async {
    await loadWorkspaces();
    await loadCurrentFolder();
  }
}

final fileBrowserProvider =
    StateNotifierProvider<FileBrowserNotifier, FileBrowserState>((ref) {
  final repo = ref.watch(fileRepositoryProvider);
  return FileBrowserNotifier(repository: repo, ref: ref);
});
