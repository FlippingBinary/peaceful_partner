import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';

enum ChatEventType {online, offline, message}

class ChatEvent {
  ChatEventType type;
  ChatPerson person;
  ChatMessage? message;
  ChatEvent({
    required this.type,
    required this.person,
    this.message,
  });
}
