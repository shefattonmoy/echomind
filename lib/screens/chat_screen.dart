import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String _apiKey = 'AIzaSyDWNwQGN1SmfgDig-S4g9lnr2dHPF-xJHo';
  final String _modelId = 'gemini-2.5-flash';

  final ChatUser _currentUser = ChatUser(id: '1', firstName: 'User');
  final ChatUser _echoMind = ChatUser(id: '2', firstName: 'EchoMind');

  List<ChatMessage> _messages = <ChatMessage>[];
  bool _showWelcomeMessage = true;
  bool _isLoading = false;
  final String _chatHistoryKey = 'chat_history';

  FlutterTts flutterTts = FlutterTts();
  bool _ttsEnabled = true;
  bool _isSpeaking = false;
  final String _ttsEnabledKey = 'tts_enabled';

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _recognizedText = '';
  bool _speechAvailable = false;
  final String _speechEnabledKey = 'speech_enabled';
  bool _speechEnabled = true;
  bool _permissionGranted = false;
  Timer? _speechTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _initTTS();
    _loadTtsPreference();
    _initSpeech();
    _loadSpeechPreference();
  }

  Future<void> _initSpeech() async {
    try {
      _speech = stt.SpeechToText();

      bool hasSpeech = await _speech.initialize(
        onStatus: (status) {
          print('Speech status: $status');
          setState(() {
            if (status == 'done' || status == 'notListening') {
              _handleSpeechStopped();
            }
          });
        },
        onError: (error) {
          print('Speech recognition error: ${error.errorMsg}');
          setState(() {
            _isListening = false;
            _recognizedText = 'Error: ${error.errorMsg}';
          });
          _cleanupSpeechTimeout();
        },
      );

      if (hasSpeech) {
        setState(() {
          _speechAvailable = true;
        });
        print('Speech recognition initialized successfully');

        await _checkPermissionStatus();
      } else {
        print('Speech recognition not available on this device');
        setState(() {
          _speechAvailable = false;
        });
      }
    } catch (e) {
      print('Error initializing speech recognition: $e');
      setState(() {
        _speechAvailable = false;
      });
    }
  }

  void _handleSpeechStopped() {
    _cleanupSpeechTimeout();
    if (_isListening) {
      setState(() {
        _isListening = false;
      });

      if (_recognizedText.trim().isNotEmpty &&
          _recognizedText != 'Listening...' &&
          !_recognizedText.startsWith('Error:')) {
        print('Sending recognized text: $_recognizedText');
        final message = ChatMessage(
          text: _recognizedText.trim(),
          user: _currentUser,
          createdAt: DateTime.now(),
        );
        _sendMessageWithContext(message);
      }

      setState(() {
        _recognizedText = '';
      });
    }
  }

  void _cleanupSpeechTimeout() {
    _speechTimeoutTimer?.cancel();
    _speechTimeoutTimer = null;
  }

  Future<void> _checkPermissionStatus() async {
    try {
      bool? hasPermission = await _speech.hasPermission;
      print('Speech permission status: $hasPermission');

      setState(() {
        _permissionGranted = hasPermission;
      });

      if (!_permissionGranted) {
        print(
          'Microphone permission not granted - will request when user tries to speak',
        );
      }
    } catch (e) {
      print('Error checking permission status: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      print('Requesting microphone permission...');

      bool? hasPermission = await _speech.hasPermission;
      if (hasPermission == false || !hasPermission) {
        bool success = await _speech.listen(
          onResult: (result) {},
          listenOptions: stt.SpeechListenOptions(partialResults: false),
        );

        if (success) {
          await _speech.stop();
        }

        await Future.delayed(Duration(seconds: 1));
        await _checkPermissionStatus();
      }
    } catch (e) {
      print('Error requesting permission: $e');
    }
  }

  Future<void> _loadSpeechPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _speechEnabled = prefs.getBool(_speechEnabledKey) ?? true;
      });
    } catch (e) {
      print('Error loading speech preference: $e');
    }
  }

  Future<void> _saveSpeechPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_speechEnabledKey, _speechEnabled);
    } catch (e) {
      print('Error saving speech preference: $e');
    }
  }

  Future<void> _toggleSpeech() async {
    setState(() {
      _speechEnabled = !_speechEnabled;
    });
    await _saveSpeechPreference();

    if (!_speechEnabled && _isListening) {
      await _stopListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || !_speechEnabled || _isListening) {
      print(
        'Cannot start listening: available=$_speechAvailable, enabled=$_speechEnabled, listening=$_isListening',
      );
      return;
    }

    bool? hasPermission = await _speech.hasPermission;
    bool permissionGranted = hasPermission ?? false;

    if (!permissionGranted) {
      print('Permission not granted, requesting...');
      await _requestPermission();

      hasPermission = await _speech.hasPermission;
      permissionGranted = hasPermission ?? false;

      if (!permissionGranted) {
        print('Permission still not granted after request');
        return;
      }
    }

    try {
      setState(() {
        _isListening = true;
        _recognizedText = 'Listening...';
        _permissionGranted = permissionGranted;
      });

      print('Starting speech recognition...');

      _cleanupSpeechTimeout();
      _speechTimeoutTimer = Timer(Duration(seconds: 30), () {
        if (_isListening) {
          print('Speech timeout reached, stopping...');
          _stopListening();
        }
      });

      bool success = await _speech.listen(
        onResult: (result) {
          print(
            'Speech result: ${result.recognizedWords} (final: ${result.finalResult})',
          );
          setState(() {
            if (result.recognizedWords.isNotEmpty) {
              _recognizedText = result.recognizedWords;
            }
          });

          if (result.finalResult) {
            print('Final result received, stopping...');
            _stopListening();
          } else {
            _speechTimeoutTimer?.cancel();
            _speechTimeoutTimer = Timer(Duration(seconds: 30), () {
              if (_isListening) {
                print('Speech timeout reached, stopping...');
                _stopListening();
              }
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(partialResults: true),
      );

      if (!success) {
        print('Failed to start listening');
        _cleanupSpeechTimeout();
        setState(() {
          _isListening = false;
          _recognizedText = 'Failed to start listening';
        });
      }
    } catch (e) {
      print('Error starting speech recognition: $e');
      _cleanupSpeechTimeout();
      setState(() {
        _isListening = false;
        _recognizedText = 'Error: $e';
      });
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    try {
      print('Stopping speech recognition...');
      await _speech.stop();
      _handleSpeechStopped();
    } catch (e) {
      print('Error stopping speech recognition: $e');
      _cleanupSpeechTimeout();
      setState(() {
        _isListening = false;
        _recognizedText = '';
      });
    }
  }

  Future<void> _initTTS() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    await flutterTts.setVolume(1.0);

    flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });

    flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
      });
      print("TTS Error: $msg");
    });
  }

  Future<void> _loadTtsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _ttsEnabled = prefs.getBool(_ttsEnabledKey) ?? true;
      });
    } catch (e) {
      print('Error loading TTS preference: $e');
    }
  }

  Future<void> _saveTtsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ttsEnabledKey, _ttsEnabled);
    } catch (e) {
      print('Error saving TTS preference: $e');
    }
  }

  Future<void> _toggleTTS() async {
    setState(() {
      _ttsEnabled = !_ttsEnabled;
    });
    await _saveTtsPreference();

    if (_ttsEnabled && _messages.isNotEmpty) {
      final latestMessage = _messages.first;
      if (latestMessage.user.id == _echoMind.id) {
        _speakMessage(latestMessage.text);
      }
    }

    if (!_ttsEnabled && _isSpeaking) {
      await flutterTts.stop();
    }
  }

  Future<void> _speakMessage(String text) async {
    if (!_ttsEnabled || text.isEmpty) return;

    try {
      await flutterTts.speak(text);
    } catch (e) {
      print('TTS Speaking Error: $e');
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
    } catch (e) {
      print('TTS Stop Error: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? chatHistoryJson = prefs.getString(_chatHistoryKey);

      if (chatHistoryJson != null && chatHistoryJson.isNotEmpty) {
        final List<dynamic> messagesJson = jsonDecode(chatHistoryJson);
        final List<ChatMessage> loadedMessages = [];

        for (final messageJson in messagesJson) {
          try {
            if (messageJson is Map<String, dynamic>) {
              if (messageJson['text'] != null && messageJson['user'] != null) {
                final chatMessage = ChatMessage.fromJson(messageJson);

                if (chatMessage.text.isNotEmpty &&
                    chatMessage.user.id.isNotEmpty) {
                  loadedMessages.add(chatMessage);
                }
              }
            }
          } catch (e) {
            print('Error parsing message: $e');
            continue;
          }
        }

        setState(() {
          _messages = loadedMessages;
          _showWelcomeMessage = _messages.isEmpty;
        });

        print('Loaded ${_messages.length} messages from history');
      } else {
        setState(() {
          _showWelcomeMessage = true;
        });
      }
    } catch (e) {
      print('Error loading chat history: $e');
      setState(() {
        _messages = [];
        _showWelcomeMessage = true;
      });
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      if (_messages.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_chatHistoryKey);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> messagesJson = _messages
          .map((message) => message.toJson())
          .toList();

      final String encodedHistory = jsonEncode(messagesJson);

      final decoded = jsonDecode(encodedHistory) as List;
      if (decoded.length == _messages.length) {
        await prefs.setString(_chatHistoryKey, encodedHistory);
        print('Saved ${_messages.length} messages to history');
      } else {
        throw Exception('Message count mismatch after encoding');
      }
    } catch (e) {
      print('Error saving chat history: $e');
    }
  }

  Future<void> _clearChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chatHistoryKey);
      setState(() {
        _messages.clear();
        _showWelcomeMessage = true;
        _isLoading = false;
      });
      print('Chat history cleared');
    } catch (e) {
      print('Error clearing chat history: $e');
    }
  }

  Future<void> _sendMessageWithContext(ChatMessage message) async {
    if (_isLoading) return;

    setState(() {
      _showWelcomeMessage = false;
      _isLoading = true;
      _messages.insert(0, message);
    });

    await _saveChatHistory();

    final String apiUrl =
        'https://generativelanguage.googleapis.com/v1beta/models/$_modelId:generateContent?key=$_apiKey';

    try {
      List<Map<String, dynamic>> conversationHistory = [];

      conversationHistory.add({
        "role": "user",
        "parts": [
          {"text": message.text},
        ],
      });

      int contextMessages = 0;
      for (int i = 1; i < _messages.length && contextMessages < 6; i++) {
        final msg = _messages[i];
        conversationHistory.insert(0, {
          "role": msg.user.id == _currentUser.id ? "user" : "model",
          "parts": [
            {"text": msg.text},
          ],
        });
        contextMessages++;
      }

      print('Sending ${conversationHistory.length} messages with context');

      final response = await post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": conversationHistory,
          "system_instruction": {
            "parts": [
              {
                "text":
                    "You are EchoMind, a helpful assistant. Keep responses concise and maintain conversation context. If the user says 'another one' or 'suggest more', continue from the previous topic.",
              },
            ],
          },
          "generationConfig": {"maxOutputTokens": 1000, "temperature": 0.7},
        }),
      );

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final generatedText =
            responseBody['candidates'][0]['content']['parts'][0]['text'];

        final responseMessage = ChatMessage(
          text: generatedText.trim(),
          user: _echoMind,
          createdAt: DateTime.now(),
        );

        setState(() {
          _messages.insert(0, responseMessage);
          _isLoading = false;
        });

        await _saveChatHistory();

        if (_ttsEnabled) {
          _speakMessage(generatedText.trim());
        }
      } else {
        final errorMessage = responseBody['error']['message'] ?? 'API Error';

        final errorResponse = ChatMessage(
          text: 'Error: $errorMessage',
          user: _echoMind,
          createdAt: DateTime.now(),
        );

        setState(() {
          _messages.insert(0, errorResponse);
          _isLoading = false;
        });

        await _saveChatHistory();
      }
    } catch (e) {
      final errorResponse = ChatMessage(
        text: 'Network error. Please check your connection.',
        user: _echoMind,
        createdAt: DateTime.now(),
      );

      setState(() {
        _messages.insert(0, errorResponse);
        _isLoading = false;
      });

      await _saveChatHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EchoMind'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  _speechEnabled ? Icons.mic : Icons.mic_off,
                  color: _speechEnabled
                      ? (_isListening ? Colors.orange : Colors.white)
                      : Colors.white70,
                ),
                onPressed: _toggleSpeech,
                tooltip: _speechEnabled ? 'Disable Speech' : 'Enable Speech',
              ),
              if (_isListening)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),

          IconButton(
            icon: Icon(
              _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled ? Colors.white : Colors.white70,
            ),
            onPressed: _toggleTTS,
            tooltip: _ttsEnabled ? 'Disable TTS' : 'Enable TTS',
          ),

          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _stopSpeaking,
              tooltip: 'Stop Speaking',
            ),

          if (_messages.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'clear') {
                  _clearChatHistory();
                } else if (value == 'tts_settings') {
                  _toggleTTS();
                } else if (value == 'speech_settings') {
                  _toggleSpeech();
                } else if (value == 'request_permission') {
                  _requestPermission();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'speech_settings',
                  child: Row(
                    children: [
                      Icon(
                        _speechEnabled ? Icons.mic : Icons.mic_off,
                        color: _speechEnabled ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(_speechEnabled ? 'Disable Speech' : 'Enable Speech'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'tts_settings',
                  child: Row(
                    children: [
                      Icon(
                        _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                        color: _ttsEnabled ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(_ttsEnabled ? 'Disable TTS' : 'Enable TTS'),
                    ],
                  ),
                ),
                if (!_permissionGranted)
                  PopupMenuItem<String>(
                    value: 'request_permission',
                    child: Row(
                      children: [
                        Icon(Icons.mic, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text('Request Microphone Permission'),
                      ],
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Clear Chat History'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isLoading)
                LinearProgressIndicator(
                  backgroundColor: Colors.lightBlue[100],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlue),
                  minHeight: 2,
                ),

              if (_isListening)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.withAlpha(50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.mic, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Listening...',
                            style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.stop, color: Colors.orange),
                            onPressed: _stopListening,
                            tooltip: 'Stop Listening',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_recognizedText.isNotEmpty &&
                          _recognizedText != 'Listening...')
                        Text(
                          _recognizedText,
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),

              if (!_permissionGranted && _speechEnabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.withAlpha(25),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Microphone permission required for voice input',
                          style: TextStyle(
                            color: Colors.red[800],
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _requestPermission,
                        child: Text(
                          'GRANT',
                          style: TextStyle(
                            color: Colors.red[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: DashChat(
                  currentUser: _currentUser,
                  onSend: (ChatMessage message) {
                    _sendMessageWithContext(message);
                  },
                  messages: _messages,
                  messageListOptions: MessageListOptions(
                    showDateSeparator: false,
                    typingBuilder: _isLoading
                        ? (context) => const SizedBox.shrink()
                        : null,
                  ),
                  inputOptions: InputOptions(
                    inputTextStyle: const TextStyle(fontSize: 16),
                    inputDecoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      suffixIcon: _speechEnabled && _permissionGranted
                          ? IconButton(
                              icon: Icon(
                                _isListening ? Icons.mic_off : Icons.mic,
                                color: _isListening
                                    ? Colors.red
                                    : Colors.lightBlue,
                                size: 28,
                              ),
                              onPressed: _isListening
                                  ? _stopListening
                                  : _startListening,
                              tooltip: _isListening
                                  ? 'Stop Listening'
                                  : 'Start Voice Input',
                            )
                          : IconButton(
                              icon: Icon(Icons.mic_off, color: Colors.grey),
                              onPressed: _requestPermission,
                              tooltip: 'Microphone permission required',
                            ),
                    ),
                    sendOnEnter: true,
                    sendButtonBuilder: (Function onSend) {
                      return IconButton(
                        onPressed: _isLoading ? null : () => onSend(),
                        icon: Icon(
                          Icons.send_sharp,
                          color: _isLoading ? Colors.grey : Colors.lightBlue,
                        ),
                      );
                    },
                    inputToolbarStyle: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    inputToolbarPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    textInputAction: TextInputAction.send,
                    alwaysShowSend: true,
                  ),
                  messageOptions: MessageOptions(
                    currentUserContainerColor: Colors.lightBlue,
                    containerColor: Colors.grey[300]!,
                    textColor: Colors.black,
                    currentUserTextColor: Colors.white,
                    messagePadding: const EdgeInsets.all(12),
                    messageDecorationBuilder:
                        (message, previousMessage, nextMessage) {
                          final isUser = message.user.id == _currentUser.id;
                          return BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: isUser ? Colors.lightBlue : Colors.grey[300],
                          );
                        },
                    onLongPressMessage: (ChatMessage message) {
                      if (message.user.id == _echoMind.id) {
                        _speakMessage(message.text);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          if (_showWelcomeMessage)
            IgnorePointer(
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hi, there! How may I help you today?',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_speechAvailable &&
                          _speechEnabled &&
                          _permissionGranted)
                        if (!_permissionGranted && _speechEnabled)
                          ElevatedButton.icon(
                            onPressed: _requestPermission,
                            icon: Icon(Icons.mic),
                            label: Text('Grant Microphone Permission'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    _speech.stop();
    _cleanupSpeechTimeout();
    super.dispose();
  }
}
