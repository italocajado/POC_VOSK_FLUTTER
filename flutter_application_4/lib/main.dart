import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VOSK Speech Recognition',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity
      ),
      home: const SpeechToTextScreen(),
    );
  }
}

class SpeechToTextScreen extends StatefulWidget {
  const SpeechToTextScreen({super.key});
  
  @override
  _SpeechToTextScreenState createState() => _SpeechToTextScreenState();
}

class _SpeechToTextScreenState extends State<SpeechToTextScreen> with WidgetsBindingObserver {
  static const int _sampleRate = 16000;
  static const String _modelName = 'vosk-model-small-pt-0.3';
  
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();
  
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  
  String _recognizedText = 'Pressione o botão para falar';
  String? _error;
  bool _isRecording = false;
  bool _isModelReady = false;
  bool _isLoading = true;
  
  static String computeTextExtraction(String message) {
    try {
      final Map<String, dynamic> jsonResult = jsonDecode(message);
      
      String? text = jsonResult['text'] ?? jsonResult['partial'];
      
      return text?.trim() ?? 'Reconhecendo...';
    } catch (e) {
      if (kDebugMode) {
        print('Text extraction error: $e');
      }
      return 'Reconhecendo...';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVosk();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      _stopRecognition();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupResources();
    super.dispose();
  }

  Future<void> _cleanupResources() async {
    try {
      await _speechService?.stop();
      await _recognizer?.dispose();
    } catch (e) {
      if (kDebugMode) {
        print('Resource cleanup error: $e');
      }
    }
  }

  Future<void> _initVosk() async {
    try {
      setState(() {
        _isLoading = true;
        _recognizedText = 'Carregando modelo...';
      });
      
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        _showPermissionError();
        return;
      }
      
      final modelPath = await _modelLoader.loadFromAssets('assets/models/$_modelName.zip')
        .catchError((error) {
          if (kDebugMode) {
            print('Model loading error: $error');
          }
          throw Exception('Falha ao carregar modelo: $error');
        });
      
      _model = await _vosk.createModel(modelPath)
        .catchError((error) {
          if (kDebugMode) {
            print('Model creation error: $error');
          }
          throw Exception('Falha ao criar modelo: $error');
        });
      
      _recognizer = await _vosk.createRecognizer(
        model: _model!, 
        sampleRate: _sampleRate,
      ).catchError((error) {
        if (kDebugMode) {
          print('Recognizer creation error: $error');
        }
        throw Exception('Falha ao criar reconhecedor: $error');
      });
      
      if (Platform.isAndroid) {
        _speechService = await _vosk.initSpeechService(_recognizer!)
          .catchError((error) {
            if (kDebugMode) {
              print('Speech service error: $error');
            }
            throw Exception('Falha ao iniciar serviço de fala: $error');
          });
        
        _speechService!.onPartial().listen(
          (partial) async {
            try {
              if (!mounted) return;
              final extractedText = await compute(computeTextExtraction, partial);
              setState(() {
                _recognizedText = extractedText;
              });
            } catch (e) {
              if (kDebugMode) {
                print('Partial text processing error: $e');
              }
            }
          },
          onError: (e) {
            if (kDebugMode) {
              print('Partial listener error: $e');
            }
          },
          cancelOnError: false,
        );

        _speechService!.onResult().listen(
          (result) async {
            try {
              if (!mounted) return;
              final extractedText = await compute(computeTextExtraction, result);
              setState(() {
                _recognizedText = extractedText;
              });
            } catch (e) {
              if (kDebugMode) {
                print('Result text processing error: $e');
              }
            }
          },
          onError: (e) {
            if (kDebugMode) {
              print('Result listener error: $e');
            }
          },
          cancelOnError: false,
        );
      }

      if (mounted) {
        setState(() {
          _isModelReady = true;
          _isLoading = false;
          _recognizedText = 'Pressione o botão para falar';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Vosk initialization error: $e');
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showPermissionError() {
    setState(() {
      _error = 'Permissão de microfone negada';
      _isLoading = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão de microfone negada'),
          backgroundColor: Colors.red,
        )
      );
    }
  }

  void _startRecognition() async {
    if (!_isModelReady || _isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modelo não está pronto'),
          backgroundColor: Colors.orange,
        )
      );
      return;
    }
    
    try {
      setState(() {
        _isRecording = true;
        _recognizedText = 'Reconhecendo...';
      });
      
      if (Platform.isAndroid) {
        await _speechService?.start();
      } else {
      }
    } catch (e) {
      if (kDebugMode) {
        print('Start recognition error: $e');
      }
      setState(() {
        _isRecording = false;
        _recognizedText = 'Erro ao iniciar reconhecimento';
      });
    }
  }

  void _stopRecognition() async {
    if (!_isModelReady || !_isRecording) return;
    
    try {
      setState(() => _isRecording = false);
      
      if (Platform.isAndroid) {
        await _speechService?.stop();
      } else {
        //para o IOS mas nem tem suporte
      }
    } catch (e) {
      if (kDebugMode) {
        print('Stop recognition error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('VOSK Speech Recognition'),
        ),
        body: Center(
          child: Text(
            'Erro: $_error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18.0, color: Colors.red),
          ),
        ),
      );
    }
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('VOSK Speech Recognition'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Inicializando reconhecimento de voz...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18.0),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('VOSK Speech Recognition'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _recognizedText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24.0),
              ),
            ),
            const SizedBox(height: 16.0),
            GestureDetector(
              onTapDown: (_) => _startRecognition(),
              onTapUp: (_) => _stopRecognition(),
              child: CircleAvatar(
                radius: 50.0,
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                child: Icon(
                  _isRecording ? Icons.mic_off : Icons.mic,
                  size: 50.0,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24.0),
            Text(
              _isModelReady 
                ? 'Modelo carregado com sucesso' 
                : 'Carregando modelo...',
              style: TextStyle(
                color: _isModelReady ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}