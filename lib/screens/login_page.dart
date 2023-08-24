import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  final Future<void> Function(String username) login;
  const LoginPage({super.key, required this.login});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _textController = TextEditingController();

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
                child: Center(
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                            hintText: "Pick a username...",
                            hintStyle: TextStyle(color: Colors.black54),
                            border: InputBorder.none),
                        // Make it possible to access the contents of this text field
                        // from the login function.
                        controller: _textController,
                      ),
                      ElevatedButton(
                        onPressed: () async =>
                            await widget.login(_textController.text),
                        child: const Text("Login"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
