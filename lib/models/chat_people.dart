import 'package:peaceful_partner/models/chat_messages.dart';

class ChatPerson {
  int id;
  String username;
  bool isOnline;
  String imageURL;
  ChatMessage? lastMessage;

  ChatPerson({
    required this.id,
    required this.username,
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

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'username': username,
      'is_online': isOnline ? 1 : 0,
      'image_url': imageURL,
    };
  }

  factory ChatPerson.fromMap(Map<String, Object?> map) {
    return ChatPerson(
      id: map['id'] as int,
      username: map['username'] as String,
      isOnline: map['is_online'] as int == 1,
      imageURL: map['image_url'] as String,
    );
  }
}
