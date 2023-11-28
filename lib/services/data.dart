import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jiffy/jiffy.dart';
import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/services/redis.dart';
import 'package:redis/redis.dart';
import 'package:sqflite/sqflite.dart';

// Create an array of an array of Strings to store default messages between fake users
const List<List<String>> defaultMessages = [
  [
    "Hey, are you free tonight?",
    "Yeah, why?",
    "Do you want to watch a movie with me?",
  ],
  [
    "I'm sorry, I can't talk right now. I'm in a meeting.",
    "A meeting? On a Friday night?",
    "Yeah, it's very important. I'll explain later.",
  ],
  [
    "Hey, did you see the latest episode of The Mandalorian?",
    "Yes, I did. It was amazing!",
    "I know, right? I loved the part where they revealed the name of Baby Yoda.",
  ],
  [
    "Hi, how are you feeling today?",
    "Not so good. I have a headache and a sore throat.",
    "Oh no, that's not good. Do you think you have a fever?",
  ],
  [
    "Hey, where are you? You were supposed to pick me up an hour ago.",
    "I'm sorry, I got stuck in traffic. There was an accident on the highway.",
    "You could have called me or texted me. I've been waiting here like an idiot.",
  ],
  [
    "Hi, I just wanted to say thank you for the birthday gift. It was very thoughtful of you.",
    "You're welcome. I'm glad you liked it.",
    "I did, but there's something I need to tell you.",
  ],
  [
    "Hey, I have some news for you.",
    "What is it?",
    "I got accepted into Harvard Law School. I'm moving to Boston next month.",
  ],
  [
    "Hey, I have a favor to ask you.",
    "Sure, what is it?",
    "Can you lend me some money? I'm a bit short this month.",
  ]
];

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
        // Create the table of people
        await db.execute(
          '''
          CREATE TABLE people(
            id INTEGER PRIMARY KEY,
            username TEXT,
            display_name TEXT,
            is_online INTEGER,
            image_url TEXT
          );
          ''',
        );
        // Create the table of messages between people
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

        // Get or create the ID for this person
        int meId;
        Command command = await getRedisCommand();
        final meIdText =
            await command.send_object(['HGET', 'username_to_id', username]);
        if (meIdText != null) {
          meId = int.parse(meIdText);
          print("Current user's id exists: $meId");
        } else {
          // The person does not previously exist, so create it
          meId = await command.send_object(['INCR', 'next_person_id']);
          await command.send_object([
            'HSET',
            'username_to_id',
            username,
            meId,
          ]);
          print("Current user's id was created: $meId");
        }

        // Create some fictional people to chat with
        final response =
            await http.get(Uri.parse('https://randomuser.me/api/?results=5'));
        if (response.statusCode != 200) {
          throw Exception('Failed to load fake users');
        }
        var randomusers = json.decode(response.body);
        int nextId = 0;
        for (var randomuser in randomusers['results']) {
          // Get the next available user id from Redis
          nextId = await command.send_object(['INCR', 'next_person_id']);
          final username = randomuser['login']['username'];
          final displayName =
              '${randomuser['name']['first']} ${randomuser['name']['last']}';
          final imageURL = randomuser['picture']['medium'];

          // Randomly choose if they are online
          final isOnline = randomuser['login']['uuid'].hashCode % 2 == 0;

          // Create a person to put in the local database
          final person = ChatPerson(
            id: nextId,
            username: username,
            displayName: displayName,
            isOnline: isOnline,
            imageURL: imageURL,
          );

          // Update Redis
          await command.send_object([
            'HSET',
            'username_to_id',
            person.username,
            person.id,
          ]);
          command.send_object([
            'SET',
            'person:${person.id}',
            json.encode(person.toMap()),
          ]);

          print("Inserting person: ${person.toMap()}");

          // Insert the person into the local database
          await db.insert(
            'people',
            person.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Create some messages between me and this person
          final messages = defaultMessages[person.id % defaultMessages.length];
          var timestamp = Jiffy.now().subtract(minutes: 15);
          for (var i = 0; i < messages.length; i++) {
            final content = messages[i];
            final message = ChatMessage(
              content: content,
              senderId: (i % 2) != 0 ? meId : person.id,
              receiverId: (i % 2) == 0 ? meId : person.id,
              timestamp: timestamp,
            );
            print("Inserting message: ${message.toMap()}");
            // Add one minute to timestamp
            timestamp = timestamp.add(minutes: 1);
            await db.insert(
              'messages',
              message.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      },
      version: 2,
    );

    command = await getRedisCommand();
    int meId;
    print("Checking if user exists");
    final meIdText =
        await command!.send_object(['HGET', 'username_to_id', username]);
    if (meIdText != null) {
      meId = int.parse(meIdText);
    } else {
      print(
          "Person does not exist. Getting next_person_id then setting value in username_to_id");
      // The person does not previously exist, so create it
      meId = await command!.send_object(['INCR', 'next_person_id']);
      await command!.send_object([
        'HSET',
        'username_to_id',
        username,
        meId,
      ]);
    }

    print("Pulling person:$meId from Redis");
    final meText = await command!.send_object(['GET', 'person:$meId']);
    Map<String, dynamic> presence;
    if (meText != null) {
      print("Person exists. Setting isOnline to true");
      presence = json.decode(meText);
      presence.update('is_online', (value) => 1);
    } else {
      print("Person does not exist. Creating new person");
      presence = ChatPerson(
              id: meId,
              username: username,
              displayName: username,
              isOnline: true)
          .toMap();
    }

    print("Calling SET on person:$meId");
    // Announce that I'm online
    await command!.send_object([
      'SET',
      'person:$meId',
      json.encode(presence),
    ]);
    // Iterate local database for people
    final people = await database!.query('people');
    for (var rawPerson in people) {
      final person = ChatPerson.fromMap(rawPerson);
      if (person.id == meId) {
        // Skip myself
        continue;
      }
      print("Calling GET on person:${person.id}");
      final personText =
          await command!.send_object(['GET', 'person:${person.id}']);
      final Map<String, dynamic> remotePerson = json.decode(personText);
      insertPerson(ChatPerson.fromMap(remotePerson));
      await command!.send_object([
        'PUBLISH',
        'chat:$meId-${person.id}',
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
          updatePersonStatus(id: data['id'], online: true);
        } else if (data['type'] == 'offline') {
          updatePersonStatus(id: data['id'], online: false);
        } else {
          print('Unknown message type: ${data['type']}');
        }
      }
    }, onError: (error) {
      print('ERROR from stream: $error');
    }, onDone: () {
      print('DONE with stream');
    });

    return ChatPerson.fromMap(presence);
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

  Future<int> updatePersonStatus(
      {required int id, required bool online}) async {
    if (database == null || database!.isOpen == false) {
      throw Exception('Database is not open');
    }
    return database!.update(
      'people',
      {'isOnline': online ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final List<Map<String, dynamic>> people =
        await database!.query('people', where: 'id = ?', whereArgs: [id]);
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
