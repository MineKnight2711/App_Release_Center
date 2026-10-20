import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A separate, bounded queue. It contains schema-approved metadata only.
class AnalyticsOutbox {
  AnalyticsOutbox(this.db);
  final Database db;

  static Future<AnalyticsOutbox> open({String? path}) async {
    sqfliteFfiInit();
    if (path == null) {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(p.join(root.path, 'analytics'));
      await directory.create(recursive: true);
      path = p.join(directory.path, 'outbox.sqlite');
    }
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE outbox (id TEXT PRIMARY KEY, owner TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL, bytes INTEGER NOT NULL)',
          );
          await db.execute('CREATE INDEX outbox_age ON outbox(created_at)');
        },
      ),
    );
    return AnalyticsOutbox(db);
  }

  Future<int> add(
    String owner,
    Map<String, Object?> event,
    DateTime now, {
    int maxEvents = 10000,
    int maxBytes = 10 * 1024 * 1024,
  }) => db.transaction((tx) async {
    final payload = jsonEncode(event);
    await tx.insert('outbox', {
      'id': event['event_id'],
      'owner': owner,
      'payload': payload,
      'created_at': now.millisecondsSinceEpoch,
      'bytes': utf8.encode(payload).length,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    var dropped = await tx.delete(
      'outbox',
      where: 'created_at < ?',
      whereArgs: [now.subtract(const Duration(days: 7)).millisecondsSinceEpoch],
    );
    while (true) {
      final size = (await tx.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(bytes),0) AS bytes FROM outbox',
      )).first;
      if ((size['n'] as int) <= maxEvents &&
          (size['bytes'] as int) <= maxBytes) {
        break;
      }
      dropped += await tx.rawDelete(
        'DELETE FROM outbox WHERE rowid IN (SELECT rowid FROM outbox ORDER BY created_at,rowid LIMIT 1)',
      );
    }
    return dropped;
  });

  Future<List<Map<String, Object?>>> batch(String owner, DateTime now) async {
    await db.delete(
      'outbox',
      where: 'created_at < ?',
      whereArgs: [now.subtract(const Duration(days: 7)).millisecondsSinceEpoch],
    );
    final rows = await db.query(
      'outbox',
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'created_at,rowid',
      limit: 50,
    );
    return rows
        .map(
          (r) => Map<String, Object?>.from(
            jsonDecode(r['payload'] as String) as Map,
          ),
        )
        .toList();
  }

  Future<void> acknowledge(String owner, Iterable<String> ids) async {
    await db.transaction((tx) async {
      for (final id in ids) {
        await tx.delete(
          'outbox',
          where: 'owner = ? AND id = ?',
          whereArgs: [owner, id],
        );
      }
    });
  }

  Future<void> clear() => db.delete('outbox');
  Future<void> retainOwner(String owner) =>
      db.delete('outbox', where: 'owner != ?', whereArgs: [owner]);
  Future<void> close() => db.close();
}
