import 'package:flutter/material.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/screens/chat_page.dart';

class HomePage extends StatelessWidget {
  final ChatPerson me;
  final void Function() logout;
  const HomePage({super.key, required this.me, required this.logout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatPage(me: me),
      bottomNavigationBar: BottomNavigationBar(
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.message),
            label: "Chats",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_work),
            label: "Channels",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_box),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
