import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'asetku.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            symbol TEXT,
            currency TEXT NOT NULL DEFAULT 'IDR',
            quantity REAL NOT NULL DEFAULT 0,
            average_buy_price REAL NOT NULL DEFAULT 0,
            current_price REAL NOT NULL DEFAULT 0,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            quantity REAL NOT NULL,
            price REAL NOT NULL,
            fee REAL NOT NULL DEFAULT 0,
            tax REAL NOT NULL DEFAULT 0,
            transaction_date TEXT NOT NULL,
            notes TEXT,
            FOREIGN KEY(asset_id) REFERENCES assets(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE price_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id INTEGER NOT NULL,
            price REAL NOT NULL,
            recorded_at TEXT NOT NULL,
            FOREIGN KEY(asset_id) REFERENCES assets(id)
          )
        ''');
      },
    );
    return _database!;
  }
}
