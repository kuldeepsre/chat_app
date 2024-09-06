import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';

class RoomChatScreen extends StatefulWidget {
  final String roomId;

  RoomChatScreen({required this.roomId});

  @override
  _RoomChatScreenState createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  TextEditingController _messageController = TextEditingController();
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool isRecording = false;
  bool isPlaying = false;
  String? _currentPlayingAudioUrl; // Track currently playing audio
  String? _currentPlayingVideoUrl; // Track currently playing video
  VideoPlayerController? _videoPlayerController;
  late CollectionReference messagesCollection;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _recorder!.openRecorder();
    _player!.openPlayer();
    messagesCollection = FirebaseFirestore.instance.collection('rooms/${widget.roomId}/messages');
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    _player!.closePlayer();
    _videoPlayerController?.dispose(); // Dispose video controller
    super.dispose();
  }

  void _sendMessage(String type, String content) {
    if (content.isNotEmpty) {
      messagesCollection.add({
        'type': type, // text, image, audio, video
        'content': content,
        'createdAt': Timestamp.now(),
      });
      _messageController.clear();
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      final storageRef = FirebaseStorage.instance.ref().child('room_videos/${DateTime.now().toString()}.mp4');
      await storageRef.putFile(File(pickedFile.path));
      String videoUrl = await storageRef.getDownloadURL();

      _sendMessage('video', videoUrl);
    }
  }

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final storageRef = FirebaseStorage.instance.ref().child('room_attachments/${DateTime.now().toString()}.png');
      await storageRef.putFile(File(pickedFile.path));
      String fileUrl = await storageRef.getDownloadURL();

      _sendMessage('image', fileUrl);
    }
  }

  Future<void> _startRecording() async {
    if (await Permission.microphone.request().isGranted) {
      setState(() {
        isRecording = true;
      });
      await _recorder!.startRecorder(toFile: 'audio_message.aac');
    }
  }

  Future<void> _stopRecording() async {
    String? filePath = await _recorder!.stopRecorder();
    setState(() {
      isRecording = false;
    });

    if (filePath != null) {
      final storageRef = FirebaseStorage.instance.ref().child('room_voice_messages/${DateTime.now().toString()}.aac');
      await storageRef.putFile(File(filePath));
      String fileUrl = await storageRef.getDownloadURL();

      _sendMessage('audio', fileUrl);
    }
  }

  Future<void> _playAudio(String url) async {
    if (_currentPlayingAudioUrl == url && isPlaying) {
      await _player!.stopPlayer();
      setState(() {
        isPlaying = false;
        _currentPlayingAudioUrl = null;
      });
    } else {
      if (isPlaying) {
        await _player!.stopPlayer();
      }
      await _player!.startPlayer(fromURI: url, codec: Codec.aacADTS);
      setState(() {
        isPlaying = true;
        _currentPlayingAudioUrl = url;
      });
    }
  }

  Future<void> _playVideo(String videoUrl) async {
    if (_videoPlayerController != null) {
      await _videoPlayerController!.pause();
    }

    if (_currentPlayingVideoUrl == videoUrl && _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
      setState(() {
        _currentPlayingVideoUrl = null;
      });
    } else {
      _videoPlayerController = VideoPlayerController.network(videoUrl);
      await _videoPlayerController!.initialize();
      _videoPlayerController!.play();

      setState(() {
        _currentPlayingVideoUrl = videoUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: messagesCollection.orderBy('createdAt', descending: true).snapshots(),
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
    bool isVideo = message['type'] == 'video';

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
          icon: Icon(
            _currentPlayingAudioUrl == message['content'] && isPlaying
                ? Icons.stop_circle
                : Icons.play_circle_outline,
          ),
          onPressed: () {
            _playAudio(message['content']);
          },
        )
            : isVideo
            ? _buildVideoPlayer(message['content'])
            : Text(message['content']),
      ),
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    return GestureDetector(
      onTap: () {
        _playVideo(videoUrl);
      },
      child: AspectRatio(
        aspectRatio: _videoPlayerController?.value.aspectRatio ?? 16 / 9,
        child: _currentPlayingVideoUrl == videoUrl && _videoPlayerController != null
            ? VideoPlayer(_videoPlayerController!)
            : Center(
          child: Icon(Icons.play_circle_outline),
        ),
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
            icon: Icon(Icons.video_library),
            onPressed: _pickVideo,
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
