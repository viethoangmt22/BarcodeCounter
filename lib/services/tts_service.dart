import 'dart:collection';

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() {
    _configure();
  }

  final FlutterTts _tts = FlutterTts();
  final Queue<String> _queue = Queue<String>();

  bool _initialized = false;
  bool _speaking = false;

  Future<void> _configure() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.55); // Increased from 0.45 to 0.55
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false); // Disabled for faster processing

    _tts.setCompletionHandler(() {
      _speaking = false;
      _speakNext();
    });

    _tts.setCancelHandler(() {
      _speaking = false;
      _speakNext();
    });

    _tts.setErrorHandler((_) {
      _speaking = false;
      _speakNext();
    });
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    if (!_initialized) {
      await _configure();
    }

    _queue.add(text);
    if (!_speaking) {
      await _speakNext();
    }
  }

  Future<void> _speakNext() async {
    if (_queue.isEmpty || _speaking) {
      return;
    }

    _speaking = true;
    final message = _queue.removeFirst();
    await _tts.speak(message);
  }

  Future<void> clearQueue() async {
    _queue.clear();
    _speaking = false;
    await _tts.stop();
  }

  Future<void> dispose() async {
    await clearQueue();
  }
}
