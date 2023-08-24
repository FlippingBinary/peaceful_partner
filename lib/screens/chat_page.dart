import 'package:flutter/material.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/services/data.dart';
import 'package:peaceful_partner/widgets/conversation_list.dart';

class ChatPage extends StatefulWidget {
  final ChatPerson me;
  const ChatPage({super.key, required this.me});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  bool alive = true;
  List<ChatPerson> people = [];

  @override
  void initState() {
    super.initState();
    _watchForPeople();
  }

  @override
  void dispose() {
    alive = false;
    super.dispose();
  }

  Future<void> _watchForPeople() async {
    while (alive) {
      final freshPeople = await _getPeople();
      setState(() {
        people = freshPeople;
      });
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<List<ChatPerson>> _getPeople() async {
    final DataService data = DataService();
    return await data.people();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      "Conversations",
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.only(
                          left: 8, right: 8, top: 2, bottom: 2),
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.pink[50],
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.add,
                            color: Colors.pink,
                            size: 20,
                          ),
                          SizedBox(
                            width: 2,
                          ),
                          Text(
                            "Add New",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            ListView.builder(
              itemCount: people.length,
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 16),
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return ConversationList(
                  me: widget.me,
                  them: people[index],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
