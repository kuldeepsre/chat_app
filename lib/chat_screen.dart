import 'dart:io';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

const String appId = 'YOUR_AGORA_APP_ID'; // Replace with your Agora App ID
const String token = 'YOUR_AGORA_TOKEN'; // Replace with your Agora Token or null if not needed
const String channelName = 'test_channel'; // Replace with your channel name

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
  int? _remoteUid;
  bool _localUserJoined = false;
  RtcEngine? _engine;
  VideoPlayerController? _videoController;
  bool isVideoPlaying = false;

  late CollectionReference messagesCollection;

  @override
  void initState() {
    super.initState();
    _initializeAgora();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _recorder!.openRecorder();
    _player!.openPlayer();
    messagesCollection = FirebaseFirestore.instance.collection('rooms/${widget.roomId}/messages');
  }

  Future<void> _initializeAgora() async {
    // Request the necessary permissions for video and audio
    await [Permission.microphone, Permission.camera].request();

    // Create the Agora engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    // Set event handlers
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('Local user joined: ${connection.localUid}');
          setState(() {
            _localUserJoined = true;
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('Remote user joined: $remoteUid');
          setState(() {
            _remoteUid = remoteUid;
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          print('Remote user left: $remoteUid');
          setState(() {
            _remoteUid = null;
          });
        },
      ),
    );

    // Enable video
    await _engine!.enableVideo();

    // Join the channel
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: ChannelMediaOptions(),
    );
  }

  @override
  void dispose() {
    _engine!.leaveChannel();
    _engine!.release();
    _recorder!.closeRecorder();
    _player!.closePlayer();
    _videoController?.dispose();
    super.dispose();
  }

  void _sendMessage(String type, String content) {
    if (content.isNotEmpty) {
      messagesCollection.add({
        'type': type, // text, image, audio, video
        'content': content,
        'createdAt': Timestamp.now(),
      });
      _messageController.clear(); // Clear input field after sending
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

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      final storageRef = FirebaseStorage.instance.ref().child('room_videos/${DateTime.now().toString()}.mp4');
      await storageRef.putFile(File(pickedFile.path));
      String fileUrl = await storageRef.getDownloadURL();

      _sendMessage('video', fileUrl);
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

  void _joinVideoCall() async {
    setState(() {
      _localUserJoined = true;
    });
    await _initializeAgora();
  }

  void _leaveVideoCall() async {
    await _engine!.leaveChannel();
    setState(() {
      _localUserJoined = false;
      _remoteUid = null;
    });
  }

  void _playVideo(String url) async {
    if (_videoController != null) {
      _videoController!.dispose();
    }
    _videoController = VideoPlayerController.network(url)
      ..initialize().then((_) {
        setState(() {
          isVideoPlaying = true;
          _videoController!.play();
        });
      });
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
          icon: Icon(Icons.play_circle_outline),
          onPressed: () {
            if (!isPlaying) {
              _player!.startPlayer(fromURI: message['content']);
              setState(() {
                isPlaying = true;
              });
            } else {
              _player!.stopPlayer();
              setState(() {
                isPlaying = false;
              });
            }
          },
        )
            : isVideo
            ? IconButton(
          icon: Icon(Icons.play_circle_filled),
          onPressed: () => _playVideo(message['content']),
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
            icon: Icon(Icons.videocam),
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

  Widget _buildVideoCallUI() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              _localUserJoined
                  ? AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine!,
                  canvas: const VideoCanvas(uid: 0),
                ),
              )
                  : Center(child: Text('Joining video call...')),

              if (_remoteUid != null)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 120,
                    height: 160,
                    child: AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(uid: _remoteUid),
                        connection: const RtcConnection(channelId: channelName),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _localUserJoined ? _leaveVideoCall : _joinVideoCall,
                child: Text(_localUserJoined ? 'Leave Call' : 'Join Call'),
              ),
            ],
          ),
        ),
      ],
    );
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
          _buildVideoCallUI(), // Video Call UI
          _buildMessageInput(),
        ],
      ),
    );
  }
}
