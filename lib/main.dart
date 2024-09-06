import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a blue toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home:  ChatScreen(),
    );
  }
}
 // For voice recording

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      isRecording = true;
    });
    await _recorder!.startRecorder(toFile: 'audio_message.aac');
  }

  Future<void> _stopRecording() async {
    setState(() {
      isRecording = false;
    });
    String? filePath = await _recorder!.stopRecorder();
    print('Recorded audio: $filePath');
    // Send the audio message to the server using socket or API
  }

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      print('Picked file: ${pickedFile.path}');
      // Send the image to the server using socket or API
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Room'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // Navigate to settings or profile
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()), // Chat List
          _buildMessageInput(), // Input Box
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      padding: EdgeInsets.all(10.0),
      itemCount: 20, // Temporary message count
      itemBuilder: (context, index) {
        bool isSentByMe = index % 2 == 0; // Temporary condition
        return Align(
          alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
          child: _buildMessageBubble(
            "Message $index",
            isSentByMe,
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(String message, bool isSentByMe) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5.0),
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: isSentByMe ? Colors.blue[200] : Colors.grey[300],
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Text(
        message,
        style: TextStyle(color: isSentByMe ? Colors.white : Colors.black),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      color: Colors.grey[200],
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file),
            onPressed: () async {
              await _pickAttachment(); // Pick and send attachment
            },
          ),
          IconButton(
            icon: isRecording ? Icon(Icons.stop) : Icon(Icons.mic),
            color: isRecording ? Colors.red : Colors.black,
            onPressed: () async {
              if (isRecording) {
                await _stopRecording(); // Stop recording
              } else {
                await _startRecording(); // Start recording
              }
            },
          ),
          const Expanded(
            child: TextField(
              decoration: InputDecoration.collapsed(
                hintText: "Type a message",
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () {
              // Send text message through socket
            },
          ),
        ],
      ),
    );
  }
}

