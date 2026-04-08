import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HoldToResetButton extends StatefulWidget {
  const HoldToResetButton({
    required this.onReset,
    this.duration = const Duration(seconds: 1),
    super.key,
  });

  final VoidCallback onReset;
  final Duration duration;

  @override
  State<HoldToResetButton> createState() => _HoldToResetButtonState();
}

class _HoldToResetButtonState extends State<HoldToResetButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerReset();
      }
    });
  }

  void _triggerReset() {
    HapticFeedback.vibrate();
    widget.onReset();
    _cancelHold();
  }

  void _startHold() {
    setState(() {
      _isHolding = true;
    });
    _controller.forward();
  }

  void _cancelHold() {
    if (_isHolding) {
      setState(() {
        _isHolding = false;
      });
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: () => _cancelHold(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: null, // GestureDetector handles logic
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
                backgroundColor: _isHolding ? Colors.red.shade50 : null,
              ),
              child: Text(_isHolding ? 'GIỮ ĐỂ RESET...' : 'ĐẶT LẠI (GIỮ 1S)'),
            ),
          ),
          if (_isHolding)
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: _controller.value,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.red.withOpacity(0.5),
                    ),
                    minHeight: 4,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
