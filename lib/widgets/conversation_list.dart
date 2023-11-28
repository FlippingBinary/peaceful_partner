import 'package:flutter/material.dart';
import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/screens/chat_detail_page.dart';

class ConversationList extends StatefulWidget {
  final ChatPerson me;
  final ChatPerson them;
  final ChatMessage? lastMessage;
  const ConversationList({
    super.key,
    required this.me,
    required this.them,
    this.lastMessage,
  });
  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ChatDetailPage(me: widget.me, them: widget.them)));
      },
      child: Container(
        padding:
            const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Opacity(
                    opacity: widget.them.isOnline ? 1.0 : 0.5,
                    child: CircleAvatar(
                      backgroundImage: NetworkImage(widget.them.imageURL),
                      maxRadius: 30,
                    ),
                  ),
                  const SizedBox(
                    width: 16,
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.them.displayName,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(
                            height: 6,
                          ),
                          Text(
                            widget.lastMessage?.content ??
                                "Start a conversation",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              "Now",
              style: TextStyle(
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
