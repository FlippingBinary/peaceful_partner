import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'package:flutter/material.dart';
import 'package:peaceful_partner/auth/secrets.dart';
import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/services/data.dart';
import 'package:webview_flutter/webview_flutter.dart';

// This is needed so that we can unfocus the text input box
final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

class ChatDetailPage extends StatefulWidget {
  final ChatPerson me;
  final ChatPerson them;

  const ChatDetailPage({super.key, required this.me, required this.them});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final DataService _data = DataService();
  List<ChatMessage> _messages = [];
  String? _alertMessage;
  String? _suggestedText;
  File? _myPicture;
  bool _isAlive = true;
  bool _isWorking = false;
  bool _isOnline = true;
  bool _isVisual = false;
  final List<num> _arousalWindow = [];
  final List<num> _valenceWindow = [];
  final ScrollController _scrollController = ScrollController();
  final ScrollController _textScrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  late final WebViewController _webViewController;
  late CameraController _cameraController;

  @override
  void initState() {
    super.initState();
    availableCameras().then((List<CameraDescription> cameras) {
      // print("Obtained list of cameras");
      _cameraController = CameraController(
        cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front),
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      // print("Created Camera Controller");
      _cameraController.initialize().then((_) {
        // print("Initialized Camera Controller");
        if (!mounted) {
          return;
        }
        setState(() {
          _isVisual = true;
        });
      });
    });
    _webViewController = WebViewController();
    _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted).then((_) {
      _webViewController.addJavaScriptChannel(
        'RequestFrame',
        onMessageReceived: (JavaScriptMessage message) {
          // print('Frame size being requested: ${message.message}');
          if (_isVisual) {
            _cameraController.takePicture().then((XFile file) {
              // print("Took picture");
              file.readAsBytes().then((bytes) {
                final currentFrame = base64Encode(bytes);
                // print("Encoded picture");
                _webViewController
                    .runJavaScript('useResolver("$currentFrame");');
                // print("Sent picture");
                File(file.path).delete().then((_) {
                  // print("Deleted picture");
                });
                // _myPicture = File(file.path);
              });
            });
          }
        },
      );
    }).then((_) {
      _webViewController.addJavaScriptChannel(
        'ArousalValence',
        onMessageReceived: (JavaScriptMessage message) {
          final Map<String, dynamic> data = json.decode(message.message);
          if (data["valence"] < 0) {
            // Inside data["affects38"] is an object with 38 keys. We need a list of the keys that have a value greater than 0.8
            // and the keys are one of the following: Afraid, Anxious, Depressed, Distressed, Enraged, Frustrated, Melancholic, Sad
            final List<String> intenseAffects = data["affects38"]
                .keys
                .where((key) =>
                    data["affects38"][key] > 0.9 &&
                    (key == "Distressed" || key == "Enraged"))
                .toList();
            if (intenseAffects.isNotEmpty) {
              setState(() {
                _alertMessage =
                    "Are you experiencing some intense emotions right now? Perhaps now is a good time to take a break and do some deep breathing, listen to music, meditate, or go for a walk.";
                _suggestedText = "";
              });
              SchedulerBinding.instance.addPostFrameCallback((_) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              });
            }
          }
        },
      );
    }).then((_) {
      _webViewController.addJavaScriptChannel(
        'EmotionAIKeyRequest',
        onMessageReceived: (JavaScriptMessage message) {
          print("Emotion AI Key Requested");
          // The library doesn't begin working until we send it the license key
          _webViewController.runJavaScript('loadEmotionAI("$emotionaiKey");');
        },
      );
    }).then((_) {
      _webViewController.loadRequest(Uri.parse(emotionaiUrl)).then((_) {
        print("Loaded Emotion AI");
      });
    });
    _fetchChatMessagesPeriodically();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _webViewController.runJavaScript('customSource.stop();');
    _isAlive = false;
    _isVisual = false;
    _isWorking = false;
    _textScrollController.dispose();
    _cameraController.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    // final ScrollController _scrollController = ScrollController();
    // final ScrollController _textScrollController = ScrollController();
    // final TextEditingController _messageController = TextEditingController();
    // late final WebViewController _webViewController;
    // late CameraController _cameraController;
    super.dispose();
  }

  Future<void> _fetchChatMessagesPeriodically() async {
    while (_isAlive) {
      await _fetchChatMessages();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _fetchChatMessages() async {
    final DataService data = DataService();
    List<ChatMessage> updatedMessages = await data.messages(1, widget.them.id);
    ChatPerson? updatedPerson = await data.person(widget.them.id);
    setState(() {
      _messages = updatedMessages;
      _isOnline = updatedPerson != null && updatedPerson.isOnline;
    });
  }

  Future<String> _getChatGPTResponse(String query) async {
    final String system = await rootBundle.loadString('assets/system.txt');
    final response =
        await http.post(Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $openaiKey',
            },
            body: json.encode({
              'model': 'gpt-3.5-turbo',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': query}
              ],
              'temperature': 1,
              'max_tokens': 256,
              'top_p': 1,
              'frequency_penalty': 0,
              'presence_penalty': 0,
            }));
    if (response.statusCode == 200) {
      return json.decode(response.body)['choices'][0]['message']['content'];
    } else {
      throw Exception('Failed to load GPT3 response');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          elevation: 0,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          flexibleSpace: SafeArea(
            child: Container(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(
                    width: 2,
                  ),
                  CircleAvatar(
                    backgroundImage: NetworkImage(widget.them.imageURL),
                    maxRadius: 20,
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          widget.them.username,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(
                          height: 6,
                        ),
                        Text(
                          _isOnline ? "Online" : "Offline",
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.settings,
                    color: Colors.black54,
                  ),
                  Visibility(
                    visible: _myPicture != null,
                    child: (_myPicture == null)
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(widget.them.imageURL),
                            maxRadius: 20,
                          )
                        : CircleAvatar(
                            backgroundImage: FileImage(_myPicture!),
                            maxRadius: 20,
                          ),
                  )
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            ListView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              children: [
                Column(
                  children: [
                    ListView.builder(
                      itemCount: _messages.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        return Container(
                          padding: const EdgeInsets.only(
                              left: 14, right: 14, top: 10, bottom: 10),
                          child: Align(
                            alignment:
                                (_messages[index].receiverId == widget.me.id
                                    ? Alignment.topLeft
                                    : Alignment.topRight),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color:
                                    (_messages[index].receiverId == widget.me.id
                                        ? Colors.grey.shade200
                                        : Colors.blue[200]),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _messages[index].content,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Visibility(
                      visible: _alertMessage != null && _suggestedText != null,
                      child: Container(
                        padding: const EdgeInsets.only(
                            left: 14, right: 14, top: 10, bottom: 10),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.yellow[200],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  _alertMessage != null ? _alertMessage! : '',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  // center the children
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  // put some padding between the children
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _alertMessage = null;
                                          _suggestedText = null;
                                        });
                                      },
                                      child: Container(
                                        height: 30,
                                        width: 30,
                                        decoration: BoxDecoration(
                                          color: Colors.lightBlue,
                                          borderRadius:
                                              BorderRadius.circular(30),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    // Spread out the two buttons a little
                                    const SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (_suggestedText != "") {
                                            // This prevents distress messages from being confused with GPT3 suggestions
                                            _messageController.text =
                                                _suggestedText!;
                                          }
                                          _alertMessage = null;
                                          _suggestedText = null;
                                        });
                                        _textScrollController.jumpTo(0);
                                      },
                                      child: Container(
                                        height: 30,
                                        width: 30,
                                        decoration: BoxDecoration(
                                          color: Colors.lightBlue,
                                          borderRadius:
                                              BorderRadius.circular(30),
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Make space for the text input bar
                    const SizedBox(height: 60),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.only(
                    left: 10, bottom: 10, top: 10, right: 10),
                height: 80,
                width: double.infinity,
                color: Colors.white,
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        height: 30,
                        width: 30,
                        decoration: BoxDecoration(
                          color: Colors.lightBlue,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 15,
                    ),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                            hintText: "Write message...",
                            hintStyle: TextStyle(color: Colors.black54),
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.only(left: 8, bottom: 8, top: 8)),
                        controller: _messageController,
                        scrollController: _textScrollController,
                      ),
                    ),
                    const SizedBox(
                      width: 15,
                    ),
                    FloatingActionButton(
                      onPressed: () async {
                        if (_messageController.text == _suggestedText) {
                          // The psychologist has already approved this text, so we don't need to send it again.
                          _data.sendMessage(ChatMessage(
                              senderId: widget.me.id,
                              receiverId: widget.them.id,
                              content: _messageController.text));
                          setState(() {
                            _alertMessage = null;
                            _suggestedText = null;
                            _messageController.clear();
                          });
                          return;
                        }
                        setState(() {
                          _isWorking = true;
                        });
                        String response =
                            await _getChatGPTResponse(_messageController.text);
                        setState(() {
                          _isWorking = false;
                        });
                        Map<String, dynamic> responseMap =
                            json.decode(response);
                        if (responseMap['type'] == 'Correction') {
                          setState(() {
                            _alertMessage = responseMap['message'];
                            _suggestedText = responseMap['revision'];
                          });
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            _scrollController.animateTo(
                              _scrollController.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                            );
                          });
                        } else if (responseMap['type'] == 'Approval') {
                          if (_scaffoldKey.currentContext != null) {
                            FocusScope.of(_scaffoldKey.currentContext!)
                                .unfocus();
                          }
                          _data.sendMessage(ChatMessage(
                              senderId: widget.me.id,
                              receiverId: widget.them.id,
                              content: _messageController.text));
                          setState(() {
                            _alertMessage = null;
                            _suggestedText = null;
                            _messageController.clear();
                          });
                        } else {
                          setState(() {
                            _alertMessage = "Sorry, I don't understand.";
                            _suggestedText = '';
                          });
                        }
                      },
                      backgroundColor: Colors.blue,
                      elevation: 0,
                      child: _isWorking
                          ? const SpinKitThreeBounce(
                              color: Colors.white,
                              size: 18,
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ));
  }
}
