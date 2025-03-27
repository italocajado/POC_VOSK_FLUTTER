import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
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
  Recognizer? _recognizer;
  SpeechService? _speechService;
  
  ValueNotifier<String> _recognizerTextNotifier = ValueNotifier<String>('Pressione o botão para falar');
  bool _isRecording = false;
  bool _isModelReady = false;
  
  // Compute text extraction in an isolate
  static String computeTextExtraction(String message) {
    try {
      final Map<String, dynamic> jsonResult = jsonDecode(message);
      
      // Prioritize text, fallback to partial
      String? text = jsonResult['text'] ?? jsonResult['partial'];
      
      return text?.trim() ?? 'Reconhecendo...';
    } catch (e) {
      print('Text extraction error: $e');
      return 'Erro ao processar texto';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVosk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recognizerTextNotifier.dispose();
    _cleanupResources();
    super.dispose();
  }

  Future<void> _cleanupResources() async {
    try {
      await _speechService?.stop();
      await _recognizer?.dispose();
    } catch (e) {
      debugPrint('Resource cleanup error: $e');
    }
  }

  Future<void> _initVosk() async {
    try {
      // Request microphone permission
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        _showPermissionError();
        return;
      }
      
      final vosk = VoskFlutterPlugin.instance();
      
      // Load model from assets
      final modelPath = await ModelLoader().loadFromAssets('assets/models/vosk-model-small-pt-0.3.zip');

      // Create model and recognizer with lower complexity
      final model = await vosk.createModel(modelPath);
      _recognizer = await vosk.createRecognizer(
        model: model, 
        sampleRate: 16000,
        // Optional: Adjust these for performance
        // complexity: RecognizerComplexity.low, // If such option exists
      );
      _speechService = await vosk.initSpeechService(_recognizer!);

      // Optimize listeners
      _speechService!.onPartial().listen((partial) async {
        final extractedText = await compute(computeTextExtraction, partial);
        _recognizerTextNotifier.value = extractedText;
      });

      _speechService!.onResult().listen((result) async {
        final extractedText = await compute(computeTextExtraction, result);
        _recognizerTextNotifier.value = extractedText;
      });

      if (mounted) {
        setState(() => _isModelReady = true);
      }
    } catch (e) {
      debugPrint('Vosk initialization error: $e');
      _handleInitializationError();
    }
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Permissão de microfone negada'),
        backgroundColor: Colors.red,
      )
    );
  }

  void _handleInitializationError() {
    if (mounted) {
      setState(() {
        _isModelReady = false;
        _recognizerTextNotifier.value = 'Erro de inicialização do modelo';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível inicializar o modelo de reconhecimento'),
          backgroundColor: Colors.red,
        )
      );
    }
  }

  void _startRecognition() async {
    if (!_isModelReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modelo não está pronto'),
          backgroundColor: Colors.orange,
        )
      );
      return;
    }
    
    try {
      setState(() => _isRecording = true);
      await _speechService?.start();
    } catch (e) {
      debugPrint('Start recognition error: $e');
      setState(() {
        _isRecording = false;
        _recognizerTextNotifier.value = 'Erro ao iniciar reconhecimento';
      });
    }
  }

  void _stopRecognition() async {
    if (!_isModelReady || !_isRecording) return;
    
    try {
      setState(() => _isRecording = false);
      await _speechService?.stop();
    } catch (e) {
      debugPrint('Stop recognition error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: ValueListenableBuilder<String>(
                valueListenable: _recognizerTextNotifier,
                builder: (context, text, child) {
                  return Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24.0)
                  );
                },
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
            )
          ],
        ),
      ),
    );
  }
}