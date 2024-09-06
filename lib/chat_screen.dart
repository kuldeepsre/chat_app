import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
class ChatScreen extends StatefulWidget {
  final String chatId; // For one-to-one chats
  final bool isGroupChat; // Whether it's a group chat or not
  final String groupId; // For group chats

  ChatScreen({this.chatId = '', this.isGroupChat = false, this.groupId = ''});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  TextEditingController _messageController = TextEditingController();
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;
  CollectionReference? messagesCollection;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
    _initializeChat();
  }

  void _initializeChat() {
    if (widget.isGroupChat) {
      messagesCollection = FirebaseFirestore.instance.collection('groups/${widget.groupId}/messages');
    } else {
      messagesCollection = FirebaseFirestore.instance.collection('chats/${widget.chatId}/messages');
    }
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    super.dispose();
  }

  // Send text message to Firestore
  void _sendMessage(String type, String content) {
    messagesCollection!.add({
      'type': type, // text, image, audio
      'content': content,
      'createdAt': Timestamp.now(),
    });
    _messageController.clear(); // Clear input field after sending
  }

  // Pick and send an image attachment
  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child('chat_attachments/${DateTime.now()}.png');
      await storageRef.putFile(File(pickedFile.path));
      String fileUrl = await storageRef.getDownloadURL();

      // Send image message
      _sendMessage('image', fileUrl);
    }
  }

  // Start recording voice message
  Future<void> _startRecording() async {
    if (await Permission.microphone.request().isGranted) {
      setState(() {
        isRecording = true;
      });
      await _recorder!.startRecorder(toFile: 'audio_message.aac');
    }
  }

  // Stop recording and send voice message
  Future<void> _stopRecording() async {
    String? filePath = await _recorder!.stopRecorder();
    setState(() {
      isRecording = false;
    });

    if (filePath != null) {
      // Upload audio file to Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child('voice_messages/${DateTime.now()}.aac');
      await storageRef.putFile(File(filePath));
      String fileUrl = await storageRef.getDownloadURL();

      // Send audio message
      _sendMessage('audio', fileUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.isGroupChat ? Text('Group Chat') : Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: messagesCollection!.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final chatDocs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: chatDocs.length,
                  itemBuilder: (context, index) {
                    var message = chatDocs[index];
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(DocumentSnapshot message) {
    bool isImage = message['type'] == 'image';
    bool isAudio = message['type'] == 'audio';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 5),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: isImage
            ? Image.network(message['content'])
            : isAudio
            ? IconButton(
          icon: Icon(Icons.play_circle_outline),
          onPressed: () {
            // Play audio logic (not implemented here)
          },
        )
            : Text(message['content']),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file),
            onPressed: _pickAttachment,
          ),
          IconButton(
            icon: isRecording ? Icon(Icons.stop) : Icon(Icons.mic),
            onPressed: () {
              if (isRecording) {
                _stopRecording();
              } else {
                _startRecording();
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () => _sendMessage('text', _messageController.text),
          ),
        ],
      ),
    );
  }
}