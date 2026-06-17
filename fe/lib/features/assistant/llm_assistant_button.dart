import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/assistant_api.dart';

class LlmAssistantButton extends StatefulWidget {
  const LlmAssistantButton({super.key});

  @override
  State<LlmAssistantButton> createState() => _LlmAssistantButtonState();
}

class _LlmAssistantButtonState extends State<LlmAssistantButton> {
  @override
  Widget build(BuildContext context) {
    final double shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final double size = shortestSide < 360 ? 46 : 52;

    return Material(
      color: Colors.transparent,
      elevation: 10,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _openAssistantSheet(context),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF33B8FF), Color(0xFFFF9AD5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            color: Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  void _openAssistantSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LlmAssistantSheet(),
    );
  }
}

class _LlmAssistantSheet extends StatefulWidget {
  const _LlmAssistantSheet();

  @override
  State<_LlmAssistantSheet> createState() => _LlmAssistantSheetState();
}

class _LlmAssistantSheetState extends State<_LlmAssistantSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AssistantMessage> _messages = <_AssistantMessage>[
    const _AssistantMessage(
      text:
          'Hi! I am AI Helper. I can suggest posts, help write polite comments, and remind you about safety rules.',
      isUser: false,
    ),
  ];

  bool _isThinking = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? preset]) async {
    final String text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _isThinking) {
      return;
    }

    setState(() {
      _messages.add(_AssistantMessage(text: text, isUser: true));
      _controller.clear();
      _isThinking = true;
    });
    _scrollToBottom();

    if (_messages.isNotEmpty) {
      try {
        final String reply = await AssistantApi.instance.sendMessage(
          message: text,
          history: _messages
              .take(_messages.length - 1)
              .map(
                (message) => <String, String>{
                  'role': message.isUser ? 'user' : 'assistant',
                  'content': message.text,
                },
              )
              .toList(),
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _messages.add(
            _AssistantMessage(
              text: reply.isEmpty
                  ? 'I do not have an answer yet. Please try asking again.'
                  : reply,
              isUser: false,
            ),
          );
          _isThinking = false;
        });
        _scrollToBottom();
        return;
      } on ApiException catch (error) {
        _addErrorMessage(error.message);
        return;
      } catch (error) {
        _addErrorMessage(error.toString());
        return;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(
        const _AssistantMessage(
          text:
              'I received your question. When the Gemini/GPT API is connected, this will reply using the backend LLM.',
          isUser: false,
        ),
      );
      _isThinking = false;
    });
    _scrollToBottom();
  }

  void _addErrorMessage(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(
        _AssistantMessage(
          text:
              'AI Helper is having trouble: $message. Please try again later or ask an adult for help.',
          isUser: false,
        ),
      );
      _isThinking = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.48,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, sheetController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF7FBFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8E4F7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _Header(onClose: () => Navigator.pop(context)),
                const _SafetyNote(),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: _messages.length + (_isThinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isThinking && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
                ),
                _QuickPrompts(onSelected: _sendMessage),
                _Composer(
                  controller: _controller,
                  isSending: _isThinking,
                  onSend: () => _sendMessage(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF33B8FF), Color(0xFFFF9AD5)],
              ),
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Helper',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A3D7C),
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Ask about posts, safety, or creative ideas',
                  style: TextStyle(color: Color(0xFF5A74A6), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFF5A74A6),
          ),
        ],
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: Color(0xFFD58A00), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nen goi LLM qua backend de bao ve API key va loc noi dung phu hop voi tre em.',
              style: TextStyle(
                color: Color(0xFF7A4E00),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<String> prompts = <String>[
      'Suggest a fun post',
      'Giup minh viet binh luan lich su',
      'Giai thich quy tac an toan',
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => ActionChip(
          onPressed: () => onSelected(prompts[index]),
          label: Text(prompts[index]),
          backgroundColor: const Color(0xFFEFF7FF),
          labelStyle: const TextStyle(
            color: Color(0xFF1A3D7C),
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide.none,
        ),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: prompts.length,
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Hoi AI Helper...',
                filled: true,
                fillColor: const Color(0xFFF0F6FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF33B8FF),
            child: IconButton(
              onPressed: isSending ? null : onSend,
              icon: isSending
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser ? const Color(0xFF33B8FF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            height: 1.35,
            color: message.isUser ? Colors.white : const Color(0xFF1A3D7C),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('AI Helper is thinking...'),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage {
  const _AssistantMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
