import 'package:sqlite3/sqlite3.dart';

import 'package:rollbar_dart/src/payload_repository/destination.dart';
import 'package:rollbar_dart/src/payload_repository/payload_record.dart';

class DbDataAccess {
  static const String dbFileName = 'rollbar_payloads.db';

  late final Database db;
  // DbDataAccess({
  //   required this.db,
  // });

  DbDataAccess initialize({required bool asPersistent}) {
    if (asPersistent) {
      db = sqlite3.open(dbFileName);
    } else {
      db = sqlite3.openInMemory();
    }

    _setupTablesAsNeeded();

    return this;
  }

  void _setupTablesAsNeeded() {
    var createTableCommnads = <String>[
      '''
      CREATE TABLE IF NOT EXISTS "${DestinationsTable.tblName}" (
        "${DestinationsTable.colEndpoint}"	TEXT NOT NULL,
        "${DestinationsTable.colAccessToken}"	TEXT NOT NULL,
        CONSTRAINT "unique_destination" UNIQUE(
          "${DestinationsTable.colEndpoint}",
          "${DestinationsTable.colAccessToken}")
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS "${PayloadRecordsTable.tblName}" (
        "${PayloadRecordsTable.colConfigJson}"	TEXT NOT NULL,
        "${PayloadRecordsTable.colPayloadJson}"	TEXT NOT NULL,
        "${PayloadRecordsTable.colCreatedAt}"	INTEGER NOT NULL,
        "${PayloadRecordsTable.colDestinationKey}"	INTEGER,
        FOREIGN KEY("${PayloadRecordsTable.colDestinationKey}")
          REFERENCES "${DestinationsTable.tblName}"("${DestinationsTable.colId}")
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
      ''',
    ];

    for (final cmd in createTableCommnads) {
      db.execute(cmd);
    }
  }

  void deleteUnusedDestinations() {
    final sqlStatement = db.prepare('''
      DELETE FROM "${DestinationsTable.tblName}" 
      WHERE NOT EXISTS (
        SELECT 
        1
        FROM 
        "${PayloadRecordsTable.tblName}"
        WHERE
        "${PayloadRecordsTable.tblName}.${PayloadRecordsTable.colDestinationKey}" 
        = "${DestinationsTable.tblName}.${DestinationsTable.colId}" 
      )
      ''');
    sqlStatement.execute([]);
    sqlStatement.dispose();
  }

  void deletePayloadRecordsOlderThan(DateTime utcExpirationTime) {
    final sqlStatement = db.prepare('''
      DELETE FROM "${PayloadRecordsTable.tblName}" 
      WHERE "${PayloadRecordsTable.colCreatedAt}" <= ?
      ''');
    sqlStatement.execute([(utcExpirationTime.millisecondsSinceEpoch / 1000)]);
    sqlStatement.dispose();
  }

  int insertDestination(Destination destination) {
    final sqlStatement = db.prepare('''
      INSERT INTO "${DestinationsTable.tblName}" (
        "${DestinationsTable.colEndpoint}", 
        "${DestinationsTable.colAccessToken}"
        )
      VALUES (?, ?)
      ''');

    sqlStatement.execute([destination.endpoint, destination.accessToken]);
    sqlStatement.dispose();

    return db.lastInsertRowId;
  }

  int insertPayloadRecord(PayloadRecord payloadRecord) {
    final sqlStatement = db.prepare('''
        INSERT INTO "${PayloadRecordsTable.tblName}" (
          "${PayloadRecordsTable.colConfigJson}", 
          "${PayloadRecordsTable.colPayloadJson}", 
          "${PayloadRecordsTable.colDestinationKey}", 
          "${PayloadRecordsTable.colCreatedAt}"
          ) 
        VALUES (?, ?, ?, ?)
        ''');

    sqlStatement.execute([
      payloadRecord.configJson,
      payloadRecord.payloadJson,
      payloadRecord.destinationID,
      payloadRecord.timestamp.millisecondsSinceEpoch / 1000
      //'strftime("%s","now")' //unixepoch time, read it by selecting: datetime(date_column,'unixepoch')
    ]);
    sqlStatement.dispose();

    return db.lastInsertRowId;
  }

  Set<Destination> selectAllDestinations() {
    final ResultSet resultSet = db.select('''
    SELECT 
    "${DestinationsTable.colId}", 
    "${DestinationsTable.colEndpoint}", 
    "${DestinationsTable.colAccessToken}" 
    FROM 
    "${DestinationsTable.tblName}"
    ''');

    final Set<Destination> destinations = <Destination>{};
    for (final row in resultSet) {
      destinations.add(_createDestination(row));
    }
    return destinations;
  }

  Destination? selectDestination(int id) {
    final ResultSet resultSet = db.select('''
    SELECT "${DestinationsTable.colId}", "${DestinationsTable.colEndpoint}", "${DestinationsTable.colAccessToken}"
    FROM "${DestinationsTable.tblName}"
    WHERE "${DestinationsTable.colId}" = ?
    ''', [id]);
    if (resultSet.isEmpty) {
      return null;
    }

    final Set<Destination> destinations = <Destination>{};
    for (final row in resultSet) {
      destinations.add(_createDestination(row));
    }
    return destinations.first;
  }

  Set<PayloadRecord> selectAllPayloadRecords() {
    final ResultSet resultSet = db.select('''
    SELECT * 
    FROM "${PayloadRecordsTable.tblName}"
    ''', []);

    final Set<PayloadRecord> payloadRecords = <PayloadRecord>{};
    for (final row in resultSet) {
      payloadRecords.add(_createPayloadRecord(row));
    }
    return payloadRecords;
  }

  Set<PayloadRecord> selectPayloadRecordsWithDestinationID(int destinationID) {
    final ResultSet resultSet = db.select('''
    SELECT * 
    FROM "${PayloadRecordsTable.tblName}"
    WHERE "${PayloadRecordsTable.colDestinationKey}" = ?
    ''', [destinationID]);

    final Set<PayloadRecord> payloadRecords = <PayloadRecord>{};
    for (final row in resultSet) {
      payloadRecords.add(_createPayloadRecord(row));
    }
    return payloadRecords;
  }

  static Destination _createDestination(Row dataRow) {
    return Destination(
        id: dataRow[DestinationsTable.colId],
        endpoint: dataRow[DestinationsTable.colEndpoint],
        accessToken: dataRow[DestinationsTable.colAccessToken]);
  }

  static PayloadRecord _createPayloadRecord(Row dataRow) {
    return PayloadRecord(
        id: dataRow[PayloadRecordsTable.colId],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (dataRow[PayloadRecordsTable.colCreatedAt] * 1000).toInt()),
        configJson: dataRow[PayloadRecordsTable.colConfigJson],
        payloadJson: dataRow[PayloadRecordsTable.colPayloadJson],
        destinationID: dataRow[PayloadRecordsTable.colDestinationKey]);
  }
}

class DestinationsTable {
  static const String tblName = 'destinations';

  static const String colId = 'rowid';
  static const String colEndpoint = 'endpoint';
  static const String colAccessToken = 'access_token';
}

class PayloadRecordsTable {
  static const String tblName = 'payload_records';

  static const String colId = 'rowid';
  static const String colConfigJson = 'config_json';
  static const String colPayloadJson = 'payload_json';
  static const String colCreatedAt = 'created_at_utc_unix_epoch_sec';
  static const String colDestinationKey = 'destination_id';
}
