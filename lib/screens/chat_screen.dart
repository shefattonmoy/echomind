// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

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

  final String _chatSessionsKey = 'chat_sessions';
  final String _currentChatIdKey = 'current_chat_id';
  List<Map<String, dynamic>> _chatSessions = [];
  String _currentChatId = '';
  bool _showChatList = false;

  FlutterTts flutterTts = FlutterTts();
  bool _ttsEnabled = true;
  bool _isSpeaking = false;
  final String _ttsEnabledKey = 'tts_enabled';


  double _speechRate = 0.5;
  double _pitch = 1.1;
  final String _speechRateKey = 'speech_rate';
  final String _pitchKey = 'voice_pitch';

  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';
  bool _speechAvailable = false;
  final String _speechEnabledKey = 'speech_enabled';
  bool _speechFeatureEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTtsPreference();
      _loadSpeechPreference();
      _loadVoicePreferences();
      _initTTS();
      _initSpeech();
      _loadChatSessions();
    });
  }


  Future<void> _loadVoicePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _speechRate = prefs.getDouble(_speechRateKey) ?? 0.5;
        _pitch = prefs.getDouble(_pitchKey) ?? 1.1;
      });
    } catch (e) {
      print('Error loading voice preferences: $e');
    }
  }


  Future<void> _saveVoicePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_speechRateKey, _speechRate);
      await prefs.setDouble(_pitchKey, _pitch);
    } catch (e) {
      print('Error saving voice preferences: $e');
    }
  }

  String _generateChatId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String _generateChatTitle(String firstMessage) {
    if (firstMessage.length > 30) {
      return '${firstMessage.substring(0, 30)}...';
    }
    return firstMessage;
  }

  Future<void> _loadChatSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? currentChatId = prefs.getString(_currentChatIdKey);

      final String? sessionsJson = prefs.getString(_chatSessionsKey);

      if (sessionsJson != null && sessionsJson.isNotEmpty) {
        final List<dynamic> sessionsList = jsonDecode(sessionsJson);
        _chatSessions = sessionsList.cast<Map<String, dynamic>>();
      } else {
        _chatSessions = [];
      }

      if (currentChatId != null && currentChatId.isNotEmpty) {
        final currentSession = _chatSessions.firstWhere(
          (session) => session['id'] == currentChatId,
          orElse: () => _createNewChatSession(),
        );
        _setCurrentChat(currentSession);
      } else {
        _createNewChatSession();
      }
    } catch (e) {
      print('Error loading chat sessions: $e');
      _createNewChatSession();
    }
  }

  Map<String, dynamic> _createNewChatSession() {
    final newChatId = _generateChatId();
    final newSession = {
      'id': newChatId,
      'title': 'New Chat',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [],
    };

    setState(() {
      _currentChatId = newChatId;
      _chatSessions.insert(0, newSession);
      _messages = [];
      _showWelcomeMessage = true;
    });

    _saveChatSessions();
    _saveCurrentChatId();
    return newSession;
  }

  void _setCurrentChat(Map<String, dynamic> session) {
    final messages = (session['messages'] as List)
        .map((msgJson) => ChatMessage.fromJson(msgJson))
        .toList();

    setState(() {
      _currentChatId = session['id'];
      _messages = messages;
      _showWelcomeMessage = messages.isEmpty;
    });
    _saveCurrentChatId();
  }

  Future<void> _saveChatSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = jsonEncode(_chatSessions);
      await prefs.setString(_chatSessionsKey, sessionsJson);
    } catch (e) {
      print('Error saving chat sessions: $e');
    }
  }

  Future<void> _saveCurrentChatId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentChatIdKey, _currentChatId);
    } catch (e) {
      print('Error saving current chat ID: $e');
    }
  }

  void _updateCurrentSession(List<ChatMessage> messages, {String? newTitle}) {
    final sessionIndex = _chatSessions.indexWhere(
      (session) => session['id'] == _currentChatId,
    );

    if (sessionIndex != -1) {
      setState(() {
        _chatSessions[sessionIndex] = {
          'id': _currentChatId,
          'title': newTitle ?? _chatSessions[sessionIndex]['title'],
          'createdAt': _chatSessions[sessionIndex]['createdAt'],
          'updatedAt': DateTime.now().toIso8601String(),
          'messages': messages.map((msg) => msg.toJson()).toList(),
        };
      });
      _saveChatSessions();
    }
  }

  void _switchToChat(String chatId) {
    final session = _chatSessions.firstWhere(
      (session) => session['id'] == chatId,
    );
    _setCurrentChat(session);
    setState(() {
      _showChatList = false;
    });
  }

  void _deleteChat(String chatId) {
    setState(() {
      _chatSessions.removeWhere((session) => session['id'] == chatId);

      if (chatId == _currentChatId) {
        if (_chatSessions.isNotEmpty) {
          _setCurrentChat(_chatSessions.first);
        } else {
          _createNewChatSession();
        }
      }
    });
    _saveChatSessions();
  }

  void _toggleChatList() {
    setState(() {
      _showChatList = !_showChatList;
    });
  }

  Future<void> _clearCurrentChat() async {
    setState(() {
      _messages.clear();
      _showWelcomeMessage = true;
      _isLoading = false;
    });
    _updateCurrentSession(_messages, newTitle: 'New Chat');
  }

  Future<void> _initTTS() async {
    try {
      var voices = await flutterTts.getVoices;

      await flutterTts.setLanguage("en-US");

      if (voices != null) {
        var femaleVoices = voices
            .where(
              (voice) =>
                  voice['name'].toString().toLowerCase().contains('female') ||
                  voice['name'].toString().toLowerCase().contains('woman') ||
                  voice['name'].toString().toLowerCase().contains('samantha') ||
                  voice['name'].toString().toLowerCase().contains('karen') ||
                  voice['name'].toString().toLowerCase().contains('victoria') ||
                  voice['name'].toString().toLowerCase().contains('ava'),
            )
            .toList();

        if (femaleVoices.isNotEmpty) {
          await flutterTts.setVoice({
            "name": femaleVoices.first['name'],
            "locale": "en-US",
          });
          print("Using female voice: ${femaleVoices.first['name']}");
        }
      }

      await flutterTts.setSpeechRate(_speechRate); 
      await flutterTts.setPitch(_pitch); 
      await flutterTts.setVolume(1.0);

      await flutterTts.setQueueMode(1);
      await flutterTts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ]);

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

      print("TTS initialized with rate: $_speechRate, pitch: $_pitch");


      await _optimizeVoiceForPlatform();
    } catch (e) {
      print("Error initializing TTS: $e");
      await flutterTts.setLanguage("en-US");
      await flutterTts.setSpeechRate(_speechRate);
      await flutterTts.setPitch(_pitch);
      await flutterTts.setVolume(1.0);
    }
  }

  Future<void> _optimizeVoiceForPlatform() async {
    try {
      await flutterTts.setSpeechRate(_speechRate);
      await flutterTts.setPitch(_pitch);
      await flutterTts.setVolume(1.0);

      await flutterTts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ]);

      await flutterTts.setQueueMode(1);
    } catch (e) {
      print("Platform-specific voice optimization failed: $e");
    }
  }

  Future<void> _adjustSpeechRate(double rate) async {
    double newRate = rate.clamp(0.3, 1.5);
    setState(() {
      _speechRate = newRate;
    });
    await flutterTts.setSpeechRate(newRate);
    await _saveVoicePreferences();
  }

  Future<void> _adjustPitch(double pitch) async {
    double newPitch = pitch.clamp(0.5, 2.0);
    setState(() {
      _pitch = newPitch;
    });
    await flutterTts.setPitch(newPitch);
    await _saveVoicePreferences();
  }

  void _showVoiceSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Voice Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Speech Rate'),
                subtitle: Slider(
                  value: _speechRate,
                  min: 0.3,
                  max: 1.5,
                  divisions: 12,
                  label: _speechRate.toStringAsFixed(1),
                  onChanged: (value) {
                    _adjustSpeechRate(value);
                    Navigator.of(context).pop();
                    _showVoiceSettingsDialog();
                  },
                ),
                trailing: Text('${_speechRate.toStringAsFixed(1)}'),
              ),
              ListTile(
                title: Text('Voice Pitch'),
                subtitle: Slider(
                  value: _pitch,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: _pitch.toStringAsFixed(1),
                  onChanged: (value) {
                    _adjustPitch(value);
                    Navigator.of(context).pop();
                    _showVoiceSettingsDialog();
                  },
                ),
                trailing: Text('${_pitch.toStringAsFixed(1)}'),
              ),
              SizedBox(height: 10),
              Text(
                '• Higher rate = faster speech\n• Higher pitch = more feminine',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
            TextButton(
              onPressed: () {
                _adjustSpeechRate(0.8);
                _adjustPitch(1.1);
                Navigator.of(context).pop();
              },
              child: Text('Reset to Default'),
            ),
          ],
        );
      },
    );
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          print('Speech status: $status');
          if (status == 'notListening' && _speechToText.isListening) {
            _stopListening();
          }

          if (status == 'done' || status == 'notListening') {
            if (_lastWords.trim().isNotEmpty) {
              _sendSpeechMessage();
            }
          }
        },
        onError: (error) {
          print('Speech error: $error');
          setState(() {
            _speechEnabled = false;
            _speechAvailable = false;
          });
        },
      );
      setState(() {
        _speechAvailable = _speechEnabled;
      });
      print('Speech recognition initialized: $_speechEnabled');
    } catch (e) {
      print('Error initializing speech: $e');
      setState(() {
        _speechAvailable = false;
      });
    }
  }

  void _startListening() async {
    if (!_speechFeatureEnabled ||
        !_speechEnabled ||
        _speechToText.isListening) {
      return;
    }

    try {
      setState(() {
        _lastWords = '';
      });

      bool success = await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: Duration(seconds: 10),
        pauseFor: Duration(seconds: 2),
        localeId: 'en-US',
        cancelOnError: true,
        partialResults: true,
        onSoundLevelChange: (level) {},
      );

      if (success) {
        setState(() {
          _speechEnabled = true;
        });
      } else {
        setState(() {
          _speechEnabled = false;
        });
        print('Failed to start listening');
      }
    } catch (e) {
      print('Error starting listening: $e');
      setState(() {
        _speechEnabled = false;
        _speechAvailable = false;
      });
    }
  }

  void _stopListening() async {
    try {
      await _speechToText.stop();
      setState(() {});

      if (_lastWords.trim().isNotEmpty) {
        _sendSpeechMessage();
      }
    } catch (e) {
      print('Error stopping listening: $e');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
    });

    print(
      'Speech result: ${result.recognizedWords}, final: ${result.finalResult}',
    );

    if (result.finalResult && _lastWords.trim().isNotEmpty) {
      Future.delayed(Duration(milliseconds: 300), () {
        if (!_speechToText.isListening) {
          _sendSpeechMessage();
        }
      });
    }
  }

  void _sendSpeechMessage() {
    if (_lastWords.trim().isEmpty || _isLoading) return;

    final message = ChatMessage(
      text: _lastWords.trim(),
      user: _currentUser,
      createdAt: DateTime.now(),
    );
    _sendMessageWithContext(message);

    setState(() {
      _lastWords = '';
    });
  }

  Future<void> _loadSpeechPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _speechFeatureEnabled = prefs.getBool(_speechEnabledKey) ?? true;
      });
    } catch (e) {
      print('Error loading speech preference: $e');
    }
  }

  Future<void> _saveSpeechPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_speechEnabledKey, _speechFeatureEnabled);
    } catch (e) {
      print('Error saving speech preference: $e');
    }
  }

  Future<void> _toggleSpeech() async {
    setState(() {
      _speechFeatureEnabled = !_speechFeatureEnabled;
    });
    await _saveSpeechPreference();

    if (!_speechFeatureEnabled && _speechToText.isListening) {
      _stopListening();
    }
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

  Future<void> _sendMessageWithContext(ChatMessage message) async {
    if (_isLoading) return;

    setState(() {
      _showWelcomeMessage = false;
      _isLoading = true;
      _messages.insert(0, message);
    });

    String? newTitle;
    if (_messages.length == 1) {
      newTitle = _generateChatTitle(message.text);
    }

    _updateCurrentSession(_messages, newTitle: newTitle);

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

      final response = await post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": conversationHistory,
          "system_instruction": {
            "parts": [
              {
                "text":
                    "You are EchoMind, a helpful assistant. You will give answer to the user according to the questions, he/she asks you. Keep responses concise and maintain conversation context. If the user says 'another one' or 'suggest more', continue from the previous topic.",
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

        _updateCurrentSession(_messages);

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

        _updateCurrentSession(_messages);
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

      _updateCurrentSession(_messages);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _toggleChatList,
          child: Row(
            children: [
              Text('EchoMind'),
              Icon(
                _showChatList ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: Colors.white,
              ),
            ],
          ),
        ),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.white),
            onPressed: _createNewChatSession,
            tooltip: 'New Chat',
          ),

          Stack(
            children: [
              IconButton(
                icon: Icon(
                  _speechFeatureEnabled ? Icons.mic : Icons.mic_off,
                  color: _speechFeatureEnabled
                      ? (_speechToText.isListening
                            ? Colors.orange
                            : Colors.white)
                      : Colors.white70,
                ),
                onPressed: _toggleSpeech,
                tooltip: _speechFeatureEnabled
                    ? 'Disable Speech'
                    : 'Enable Speech',
              ),
              if (_speechToText.isListening)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
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
                  _clearCurrentChat();
                } else if (value == 'tts_settings') {
                  _toggleTTS();
                } else if (value == 'speech_settings') {
                  _toggleSpeech();
                } else if (value == 'view_chats') {
                  _toggleChatList();
                } else if (value == 'voice_faster') {
                  _adjustSpeechRate(_speechRate + 0.1); // Increase speed
                } else if (value == 'voice_slower') {
                  _adjustSpeechRate(_speechRate - 0.1); // Decrease speed
                } else if (value == 'voice_settings') {
                  _showVoiceSettingsDialog();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'view_chats',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Chat History'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'voice_settings',
                  child: Row(
                    children: [
                      Icon(Icons.record_voice_over, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text('Voice Settings'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'voice_faster',
                  child: Row(
                    children: [
                      Icon(Icons.fast_forward, color: Colors.green),
                      const SizedBox(width: 8),
                      Text('Faster Speech'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'voice_slower',
                  child: Row(
                    children: [
                      Icon(Icons.fast_rewind, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('Slower Speech'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'speech_settings',
                  child: Row(
                    children: [
                      Icon(
                        _speechFeatureEnabled ? Icons.mic : Icons.mic_off,
                        color: _speechFeatureEnabled
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _speechFeatureEnabled
                            ? 'Disable Speech'
                            : 'Enable Speech',
                      ),
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
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Clear Current Chat'),
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
              if (_showChatList)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Text(
                              'Chat History',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(Icons.close),
                              onPressed: _toggleChatList,
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _chatSessions.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Lottie.asset(
                                      'assets/lottie/empty_chat.json',
                                      width: 100,
                                      height: 100,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.chat,
                                              size: 50,
                                              color: Colors.grey,
                                            );
                                          },
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No chat history yet',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _chatSessions.length,
                                itemBuilder: (context, index) {
                                  final session = _chatSessions[index];
                                  final isCurrent =
                                      session['id'] == _currentChatId;
                                  final messages =
                                      (session['messages'] as List).length;
                                  final updatedAt = DateTime.parse(
                                    session['updatedAt'],
                                  );

                                  return ListTile(
                                    leading: Icon(Icons.chat),
                                    title: Text(
                                      session['title'],
                                      style: TextStyle(
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$messages messages • ${DateFormat('MMM dd, HH:mm').format(updatedAt)}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isCurrent)
                                          Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _deleteChat(session['id']),
                                          tooltip: 'Delete Chat',
                                        ),
                                      ],
                                    ),
                                    onTap: () => _switchToChat(session['id']),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

              if (_isLoading)
                SizedBox(
                  height: 80,
                  child: Center(
                    child: Lottie.asset(
                      'assets/lottie/loading.json',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.lightBlue,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              if (_speechToText.isListening)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.withAlpha(50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Lottie.asset(
                            'assets/lottie/voice_wave.json',
                            width: 40,
                            height: 40,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.mic,
                                color: Colors.orange,
                                size: 40,
                              );
                            },
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Listening... Speak now',
                            style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: const Icon(Icons.stop, color: Colors.orange),
                            onPressed: _stopListening,
                            tooltip: 'Stop Listening',
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_lastWords.isNotEmpty)
                        Text(
                          _lastWords,
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 16,
                          ),
                        ),
                      SizedBox(height: 8),
                      Text(
                        'Tap stop or wait for auto-complete',
                        style: TextStyle(
                          color: Colors.orange[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              if (!_speechEnabled && _speechFeatureEnabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.withAlpha(25),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Speech recognition not available on this device',
                          style: TextStyle(
                            color: Colors.red[800],
                            fontSize: 14,
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
                    inputTextStyle: TextStyle(fontSize: 16),
                    inputDecoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      suffixIcon: _speechFeatureEnabled && _speechEnabled
                          ? IconButton(
                              icon: Icon(
                                _speechToText.isListening
                                    ? Icons.mic_off
                                    : Icons.mic,
                                color: _speechToText.isListening
                                    ? Colors.red
                                    : Colors.lightBlue,
                                size: 28,
                              ),
                              onPressed: _speechToText.isListening
                                  ? _stopListening
                                  : _startListening,
                              tooltip: _speechToText.isListening
                                  ? 'Stop Listening'
                                  : 'Start Voice Input',
                            )
                          : _speechFeatureEnabled
                          ? IconButton(
                              icon: Icon(Icons.mic_off, color: Colors.grey),
                              onPressed: null,
                              tooltip: 'Speech not available',
                            )
                          : null,
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
                    inputToolbarPadding: EdgeInsets.symmetric(
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
                    messagePadding: EdgeInsets.all(12),
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

          if (_showWelcomeMessage && !_showChatList)
            IgnorePointer(
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Lottie.asset(
                        'assets/chatbot.json',
                        width: 150,
                        height: 150,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.smart_toy,
                            color: Colors.lightBlue,
                            size: 100,
                          );
                        },
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Hi, there! How may I help you today?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),
                      if (_chatSessions.length > 1)
                        Text(
                          'You have ${_chatSessions.length - 1} previous chat(s)',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
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
    _speechToText.stop();
    super.dispose();
  }
}
