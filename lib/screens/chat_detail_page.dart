import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'package:flutter/material.dart';
import 'package:peaceful_partner/auth/secrets.dart';
import 'package:peaceful_partner/models/chat_messages.dart';
import 'package:peaceful_partner/models/chat_people.dart';
import 'package:peaceful_partner/models/self_help_hint.dart';
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

// Define a list of self care messages and corresponding icons
const List<SelfHelpHint> _selfCareMessages = [
  SelfHelpHint(
      icon: Icons.face,
      hint: "You are doing great, but don't forget to take care of yourself."),
  SelfHelpHint(
      icon: Icons.pause_circle,
      hint: "Sometimes, a little pause can make a big difference"),
  SelfHelpHint(
      icon: Icons.favorite,
      hint: "Take a moment to love yourself, no matter what happens."),
  SelfHelpHint(
      icon: Icons.music_note,
      hint: "Music can be a great way to relax and restore your strength."),
  SelfHelpHint(
      icon: Icons.local_florist,
      hint:
          "Take a moment to appreciate the beauty around you. This chat can wait."),
];

class _ChatDetailPageState extends State<ChatDetailPage> {
  final DataService _data = DataService();
  List<ChatMessage> _messages = [];
  int? _selfCareMessage;
  String? _adviceMessage;
  String? _revisionText;
  File? _myPicture;
  bool _isAlive = true;
  bool _isWorking = false;
  bool _isOnline = true;
  bool _isVisual = false;
  Timer? _timer;
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
      return _webViewController.addJavaScriptChannel(
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
      return _webViewController.addJavaScriptChannel(
        'ArousalValence',
        onMessageReceived: (JavaScriptMessage message) {
          final Map<String, dynamic> data = json.decode(message.message);
          if (data["valence"] < -0.7) {
            // // Inside data["affects38"] is an object with 38 keys. We need a list of the keys that have a value greater than 0.8
            // // and the keys are one of the following: Afraid, Anxious, Depressed, Distressed, Enraged, Frustrated, Melancholic, Sad
            // final List<String> intenseAffects = data["affects38"]
            //     .keys
            //     .where((key) => data["affects38"][key] > 0.9)
            //     .toList();
            // if (intenseAffects.isNotEmpty) {
              setState(() {
                _timer?.cancel();
                _timer = Timer(const Duration(seconds: 10), () {
                  setState(() {
                    _selfCareMessage = null;
                  });
                });
                // Pick a random message in the list if one has not already been picked
                _selfCareMessage ??= Random().nextInt(_selfCareMessages.length);
              });
              SchedulerBinding.instance.addPostFrameCallback((_) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              });
            // }
          }
        },
      );
    }).then((_) {
      return _webViewController.addJavaScriptChannel(
        'EmotionAIError',
        onMessageReceived: (JavaScriptMessage message) {
          print("Emotion AI Error: ${message.message}");
        },
      );
    }).then((_) {
      return _webViewController.addJavaScriptChannel(
        'EmotionAIKeyRequest',
        onMessageReceived: (JavaScriptMessage message) {
          print("Emotion AI Key Requested");
          // The library doesn't begin working until we send it the license key
          _webViewController.runJavaScript('loadEmotionAI("$emotionaiKey");');
        },
      );
    }).then((_) {
      return _webViewController.loadRequest(Uri.parse(emotionaiUrl)).then((_) {
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
    List<ChatMessage> updatedMessages =
        await data.messages(widget.me.id, widget.them.id);
    ChatPerson? updatedPerson = await data.person(widget.them.id);
    setState(() {
      _messages = updatedMessages;
      _isOnline = updatedPerson?.isOnline ?? false;
    });
  }

  Future<String> _getChatGPTResponse(String systemFile, String query) async {
    final String system = await rootBundle.loadString(systemFile);
    final response =
        await http.post(Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $openaiKey',
            },
            body: json.encode({
              'model': 'gpt-3.5-turbo-1106',
              'response_format': {'type': "json_object"},
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
    if (response.statusCode != 200) {
      var body = response.body;
      print("Failed to load GPT3 response: $body");
      throw Exception('Failed to load GPT3 response');
    }
    var gptResponse = json.decode(response.body)['choices'][0];
    // Check to make sure the finish_reason is not "length", which means the message was too long
    if (gptResponse['finish_reason'] == 'length') {
      print("GPT3 response was too long: $gptResponse");
      return json.encode({
        'command': 'reject',
        'advice':
            'GPT response to your message was too long. Please try again.',
        'revision': query,
      });
    }
    return gptResponse['message']['content'];
  }

  Map<String, String>? _parseCensorResponse(String response) {
    // The response contains a JSON object with the following keys:
    // - command: a string containing either "accept" or "reject"
    // - advice: a string containing the advice to give the user
    // - revision: a string containing the revised message to send to the user
    // Parse the response and return the advice and revision if the command is "reject"
    var responseJson = json.decode(response);
    if (responseJson['command'] == 'accept') {
      // We just ignore the model's advice if it says to accept the message
      return null;
    } else if (responseJson['command'] == 'reject') {
      return {
        'advice': responseJson['advice'],
        'revision': responseJson['revision']
      };
    } else {
      print(
          "Failed to parse censor response because it didn't contain a valid command: $response");
      return {
        'advice':
            "Failed to parse GPT response because it didn't contain a valid command: $response",
        'revision': ""
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        bottom: true,
        child: Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              elevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              toolbarHeight: 75,
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
                      Opacity(
                        opacity: _isOnline ? 1.0 : 0.5,
                        child: CircleAvatar(
                          backgroundImage:
                              NetworkImage(widget.them.imageURL),
                          maxRadius: 20,
                        ),
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
                              widget.them.displayName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(
                              height: 6,
                            ),
                            Text(
                              _isOnline ? "Online" : "Offline",
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13),
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
                                backgroundImage:
                                    NetworkImage(widget.them.imageURL),
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
                              padding: EdgeInsets.only(
                                  left: (_messages[index].receiverId ==
                                          widget.me.id
                                      ? 14
                                      : 28),
                                  right: (_messages[index].receiverId !=
                                          widget.me.id
                                      ? 14
                                      : 28),
                                  top: 10,
                                  bottom: 10),
                              child: Align(
                                alignment:
                                    (_messages[index].receiverId == widget.me.id
                                        ? Alignment.topLeft
                                        : Alignment.topRight),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.only(
                                      topLeft: (_messages[index].receiverId ==
                                              widget.me.id
                                          ? const Radius.circular(0)
                                          : const Radius.circular(20)),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: const Radius.circular(20),
                                      bottomRight:
                                          (_messages[index].receiverId ==
                                                  widget.me.id
                                              ? const Radius.circular(20)
                                              : const Radius.circular(0)),
                                    ),
                                    color: (_messages[index].receiverId ==
                                            widget.me.id
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
                          visible: _adviceMessage != null,
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
                                      _adviceMessage != null
                                          ? _adviceMessage!
                                          : '',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      // center the children
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      // put some padding between the children
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _adviceMessage = null;
                                              _revisionText = null;
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
                                              if (_revisionText != null &&
                                                  _revisionText != "") {
                                                _messageController.text =
                                                    _revisionText!;
                                              }
                                              _adviceMessage = null;
                                              _revisionText = null;
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
                        Visibility(
                          visible: _selfCareMessage != null,
                          child: Container(
                            padding: const EdgeInsets.only(
                                left: 14, right: 14, top: 10, bottom: 10),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: Colors.pink[200],
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Row(children: [
                                      Icon(
                                          _selfCareMessages[
                                                  _selfCareMessage ?? 0]
                                              .icon,
                                          color: Colors.white),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                            _selfCareMessages[
                                                    _selfCareMessage ?? 0]
                                                .hint,
                                            style:
                                                const TextStyle(fontSize: 15)),
                                      )
                                    ])
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
                                contentPadding: EdgeInsets.only(
                                    left: 8, bottom: 8, top: 8)),
                            controller: _messageController,
                            scrollController: _textScrollController,
                          ),
                        ),
                        const SizedBox(
                          width: 15,
                        ),
                        FloatingActionButton(
                          onPressed: () async {
                            if (_messageController.text.trim() == "") {
                              return;
                            }
                            if (_messageController.text == _revisionText) {
                              // The psychologist has already approved this text, so we don't need to send it again.
                              _data.sendMessage(ChatMessage(
                                  senderId: widget.me.id,
                                  receiverId: widget.them.id,
                                  content: _messageController.text));
                              setState(() {
                                _adviceMessage = null;
                                _revisionText = null;
                                _messageController.clear();
                              });
                              return;
                            }
                            setState(() {
                              _isWorking = true;
                            });
                            String rawResponse = await _getChatGPTResponse(
                                "assets/system-censor.txt",
                                _messageController.text);
                            setState(() {
                              _isWorking = false;
                            });
                            var response =
                                _parseCensorResponse(rawResponse.trim());
                            if (response == null) {
                              // The message was approved, so we can send it.
                              if (_scaffoldKey.currentContext != null) {
                                FocusScope.of(_scaffoldKey.currentContext!)
                                    .unfocus();
                              }
                              _data.sendMessage(ChatMessage(
                                  senderId: widget.me.id,
                                  receiverId: widget.them.id,
                                  content: _messageController.text));
                              setState(() {
                                _adviceMessage = null;
                                _revisionText = null;
                                _messageController.clear();
                              });
                            } else {
                              // The message was rejected, so we need to show the suggested text and advice.
                              setState(() {
                                _adviceMessage = response['advice'];
                                _revisionText = response['revision'];
                              });
                              SchedulerBinding.instance
                                  .addPostFrameCallback((_) {
                                _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                );
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
            )));
  }
}
