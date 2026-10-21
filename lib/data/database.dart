import 'package:drift/drift.dart';

import 'connection.dart';

/// Explicit SQL keeps the storage schema readable without generated model copies.
class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in [
        'CREATE TABLE decks (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        'CREATE TABLE cards (id TEXT PRIMARY KEY, deck_id TEXT NOT NULL, source TEXT NOT NULL, search_text TEXT NOT NULL, chapter TEXT NOT NULL, tags TEXT NOT NULL, plan TEXT NOT NULL, due_at INTEGER, enrolled_at INTEGER NOT NULL, first_learned INTEGER, payload TEXT NOT NULL)',
        'CREATE INDEX cards_deck ON cards(deck_id, chapter)',
        'CREATE INDEX cards_due ON cards(plan, due_at)',
        'CREATE INDEX cards_new ON cards(deck_id, plan, first_learned, enrolled_at)',
        'CREATE TABLE reviews (id TEXT PRIMARY KEY, card_id TEXT NOT NULL, deck_id TEXT NOT NULL, reviewed_at INTEGER NOT NULL, grade INTEGER NOT NULL, kind TEXT NOT NULL, elapsed_ms INTEGER NOT NULL, payload TEXT NOT NULL)',
        'CREATE INDEX reviews_card ON reviews(card_id, reviewed_at)',
        'CREATE INDEX reviews_day ON reviews(kind, reviewed_at)',
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        'CREATE TABLE media (id TEXT PRIMARY KEY, name TEXT NOT NULL, bytes BLOB NOT NULL)',
      ]) {
        await customStatement(statement);
      }
    },
  );
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args.map((e) => Variable(e)).toList(),
  ).get()).map((e) => e.data).toList();
}
