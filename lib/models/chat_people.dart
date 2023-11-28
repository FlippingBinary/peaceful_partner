import 'package:peaceful_partner/models/chat_messages.dart';

class ChatPerson {
  int id;
  String username;
  String displayName;
  bool isOnline;
  String imageURL;
  ChatMessage? lastMessage;

  ChatPerson({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isOnline,
    this.imageURL = "",
    this.lastMessage,
  }) {
    if (imageURL == "") {
      // For this demo, we'll just use randomuser.me and alternate male and female
      final gender = id % 2 == 0 ? 'men' : 'women';
      imageURL = "https://randomuser.me/api/portraits/$gender/$id.jpg";
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'is_online': isOnline ? 1 : 0,
      'image_url': imageURL,
    };
  }

  factory ChatPerson.fromMap(Map<String, Object?> map) {
    if (map['id'] == null) {
      throw ArgumentError('Missing required property id in ChatPerson.fromMap');
    }
    if (map['username'] == null) {
      throw ArgumentError(
          'Missing required property username in ChatPerson.fromMap');
    }
    if (map['display_name'] == null) {
      throw ArgumentError(
          'Missing required property display_name in ChatPerson.fromMap');
    }
    if (map['is_online'] == null) {
      throw ArgumentError(
          'Missing required property is_online in ChatPerson.fromMap');
    }
    return ChatPerson(
      id: map['id'] as int,
      username: map['username'] as String,
      displayName: map['display_name'] as String,
      isOnline: map['is_online'] as int == 1,
      imageURL: map['image_url'] == null ? "" : map['image_url'] as String,
    );
  }
}
