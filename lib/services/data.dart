import 'dart:convert';
import 'dart:io';

import 'package:jiffy/jiffy.dart';
import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/services/redis.dart';
import 'package:redis/redis.dart';
import 'package:sqflite/sqflite.dart';

class DataService {
  DataService._();

  static final DataService _instance = DataService._();

  factory DataService() => _instance;

  // Variables
  Database? database;
  ChatPerson? me;
  Command? command;
  PubSub? pubsub;
  Stream<dynamic>? stream;

  Future<ChatPerson> join(String username) async {
    if (me != null) {
      throw Exception('Already joined');
    }
    // Delete the write-ahead log file if it exists
    File walFile = File('peaceful_partner.db-wal');
    if (await walFile.exists()) {
      await walFile.delete();
    }
    // Delete the rollback journal file if it exists
    File journalFile = File('peaceful_partner.db-journal');
    if (await journalFile.exists()) {
      await journalFile.delete();
    }
    database = await openDatabase(
      'peaceful_partner.db',
      onCreate: (db, version) async {
        await db.execute(
          '''
          CREATE TABLE people(
            id INTEGER PRIMARY KEY,
            username TEXT,
            is_online INTEGER,
            image_url TEXT
          );
          ''',
        );
        await db.execute(
          '''
          CREATE TABLE messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT,
            sender_id INTEGER,
            receiver_id INTEGER,
            timestamp TEXT,
            FOREIGN KEY (sender_id) REFERENCES people (id),
            FOREIGN KEY (receiver_id) REFERENCES people (id)
          );
          ''',
        );
      },
      version: 2,
    );

    command = await getRedisCommand();
    int meId;
    print("Calling EXISTS on username_to_id");
    final meIdExisting =
        await command!.send_object(['EXISTS', 'username_to_id', username]);
    if (meIdExisting == 1) {
      print("Person exists. Calling HGET");
      // The person already exists, so load it up
      final meIdText =
          await command!.send_object(['HGET', 'username_to_id', username]);

      meId = int.parse(meIdText);
    } else if (meIdExisting == 0) {
      print("Person does not exist. Calling INCR");
      // The person does not previously exist, so create it
      meId = await command!.send_object(['INCR', 'next_person_id']);
      // meId = int.parse(meIdText);
      print("Calling HSET");
      await command!.send_object([
        'HSET',
        'username_to_id',
        username,
        meId,
      ]);
    } else {
      print('Unexpected response from Redis: $meIdExisting');
      throw Exception('Unexpected response from Redis');
    }

    print("Calling EXISTS on person:$meId");
    final meExisting = await command!.send_object(['EXISTS', 'person:$meId']);
    Map<String, dynamic> presence;
    if (meExisting == 1) {
      print("Person exists. Calling GET on person:$meId");
      // The person already exists, so load it up
      final meText = await command!.send_object(['GET', 'person:$meId']);
      presence = json.decode(meText);
      presence.update('isOnline', (value) => true);
    } else if (meExisting == 0) {
      print("Person does not exist. Creating new person");
      presence = {
        'id': meId,
        'username': username,
        'isOnline': true,
        'people': [],
      };
    } else {
      print('Unexpected response from Redis: $meExisting');
      throw Exception('Unexpected response from Redis');
    }

    print("Calling SET on person:$meId");
    // Announce that I'm online
    command!.send_object([
      'SET',
      'person:$meId',
      json.encode(presence),
    ]);
    for (int personId in presence['people']) {
      print("Calling GET on person:$personId");
      final personText =
          await command!.send_object(['GET', 'person:$personId']);
      print("Received: $personText");
      final Map<String, dynamic> person = json.decode(personText);
      // get info about the person in the meantime
      insertPerson(ChatPerson(
        id: person['id'],
        username: person['username'],
        isOnline: person['isOnline'],
      ));
      command!.send_object([
        'PUBLISH',
        'chat:$meId-$personId',
        json.encode({
          'type': 'online',
          'id': meId,
        })
      ]);
    }

    pubsub = PubSub(command!);
    pubsub!.psubscribe(['chat:*-$meId']);
    stream = pubsub!.getStream();

    stream!.listen((event) {
      print('EVENT RECEIVED: ${json.encode(event)}');
      var kind = event[0];
      if (kind == 'pmessage') {
        Map<String, dynamic> data = json.decode(event[3]);
        if (data['type'] == 'chat') {
          // store the chat message in the Sqlite database
          insertMessage(ChatMessage(
            content: data['content'],
            senderId: data['id'],
            receiverId: meId,
            timestamp: Jiffy.now(),
          ));
        } else if (data['type'] == 'online') {
          insertPerson(ChatPerson(
            id: data['id'],
            username: data['username'],
            isOnline: true,
            imageURL: data['imageURL'],
          ));
        } else if (data['type'] == 'offline') {
          insertPerson(ChatPerson(
            id: data['id'],
            username: data['username'],
            isOnline: false,
            imageURL: data['imageURL'],
          ));
        } else {
          print('Unknown message type: ${data['type']}');
        }
      }
    }, onError: (error) {
      print('ERROR from stream: $error');
    }, onDone: () {
      print('DONE with stream');
    });

    return ChatPerson(
      id: presence['id'],
      username: presence['username'],
      isOnline: true,
    );
  }

  void leave() {
    if (database != null && database!.isOpen) {
      database!.close();
    }
    pubsub!.punsubscribe(['chat:*']);
    command!.get_connection().close();
    database = null;
    pubsub = null;
    command = null;
    me = null;
    stream = null;
  }

  Future<int> insertPerson(ChatPerson person) async {
    if (database == null || database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    return database!.insert(
      'people',
      person.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChatPerson?> person(int id) async {
    if (database == null || database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    final List<Map<String, dynamic>> people = await database!.query('people', where: 'id = ?', whereArgs: [id]);
    return people.map((element) => ChatPerson.fromMap(element)).toList().first;
  }

  Future<List<ChatPerson>> people() async {
    if (database == null || database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    final List<Map<String, dynamic>> people = await database!.query('people');
    return people.map((element) => ChatPerson.fromMap(element)).toList();
  }

  Future<int> insertMessage(ChatMessage message) async {
    if (database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    return database!.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> sendMessage(ChatMessage message) async {
    final command = await getRedisCommand();
    command.send_object([
      'PUBLISH',
      'chat:${message.senderId}-${message.receiverId}',
      json.encode({
        'type': 'chat',
        'id': message.senderId,
        'content': message.content,
      })
    ]);
    command.get_connection().close();
    return insertMessage(message);
  }

  Future<List<ChatMessage>> messages(int meId, int themId) async {
    if (database == null || database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    final List<Map<String, dynamic>> message = await database!.query('messages',
        where:
            '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)',
        whereArgs: [meId, themId, themId, meId]);
    return message.map((element) => ChatMessage.fromMap(element)).toList();
  }
}
