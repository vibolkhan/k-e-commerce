import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../domain/content.dart';

abstract interface class ContentRepository {
  Future<List<AdminBanner>> banners();
  Future<List<AdminCollection>> collections();
  Future<List<ContentPageModel>> pages();
  Future<void> saveBanner(AdminBanner banner);
  Future<void> saveCollection(AdminCollection collection);
  Future<void> savePage(ContentPageModel page);
  Future<String> uploadBanner(String name, Uint8List bytes);
}

class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<AdminBanner>> banners() async => [
    for (final row in await client.from('banners').select().order('sort'))
      AdminBanner.fromRow(row),
  ];
  @override
  Future<List<AdminCollection>> collections() async => [
    for (final row in await client.from('collections').select().order('sort'))
      AdminCollection.fromRow(row),
  ];
  @override
  Future<List<ContentPageModel>> pages() async => [
    for (final row in await client.from('content_pages').select().order('slug'))
      ContentPageModel.fromRow(row),
  ];

  Future<void> _upsert(
    String table,
    String id,
    Map<String, dynamic> row,
  ) async {
    final data = {...row, if (id.isNotEmpty) 'id': id};
    await client.from(table).upsert(data);
  }

  @override
  Future<void> saveBanner(AdminBanner value) =>
      _upsert('banners', value.id, value.toRow());
  @override
  Future<void> saveCollection(AdminCollection value) =>
      _upsert('collections', value.id, value.toRow());
  @override
  Future<void> savePage(ContentPageModel value) =>
      _upsert('content_pages', value.id, value.toRow());
  @override
  Future<String> uploadBanner(String name, Uint8List bytes) async {
    final safe = name.toLowerCase().replaceAll(RegExp('[^a-z0-9._-]'), '-');
    final path = '${DateTime.now().microsecondsSinceEpoch}-$safe';
    await client.storage
        .from('banners')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }
}

class OfflineContentRepository implements ContentRepository {
  const OfflineContentRepository();
  Never _offline() => throw StateError('Supabase is not configured');
  @override
  Future<List<AdminBanner>> banners() async => const [];
  @override
  Future<List<AdminCollection>> collections() async => const [];
  @override
  Future<List<ContentPageModel>> pages() async => const [];
  @override
  Future<void> saveBanner(AdminBanner value) async => _offline();
  @override
  Future<void> saveCollection(AdminCollection value) async => _offline();
  @override
  Future<void> savePage(ContentPageModel value) async => _offline();
  @override
  Future<String> uploadBanner(String name, Uint8List bytes) async => _offline();
}

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineContentRepository();
  }
  return SupabaseContentRepository(Supabase.instance.client);
});
