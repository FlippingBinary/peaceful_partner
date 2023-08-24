import 'package:jiffy/jiffy.dart';

class ChatMessage {
  int? id;
  String content;
  int senderId;
  int receiverId;
  Jiffy timestamp;

  ChatMessage({
    this.id,
    required this.content,
    required this.senderId,
    required this.receiverId,
    timestamp,
  }) : timestamp = timestamp ?? Jiffy.now();

  Map<String, Object?> toMap() {
    return {
      // don't include id in the map if it is null
      if (id != null) 'id': id,
      'content': content,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'timestamp': timestamp.format(pattern: 'yyyy-MM-dd HH:mm:ss'),
    };
  }

  factory ChatMessage.fromMap(Map<String, Object?> map) {
    if (map['id'] == null) {
      return ChatMessage(
        content: map['content'] as String,
        senderId: map['sender_id'] as int,
        receiverId: map['receiver_id'] as int,
        timestamp: Jiffy.parse(map['timestamp'] as String),
      );
    } else {
      return ChatMessage(
        id: map['id'] as int,
        content: map['content'] as String,
        senderId: map['sender_id'] as int,
        receiverId: map['receiver_id'] as int,
        timestamp: Jiffy.parse(map['timestamp'] as String),
      );
    }
  }
}
