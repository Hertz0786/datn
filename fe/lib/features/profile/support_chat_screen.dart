import 'package:flutter/material.dart';

import '../../core/models/support_message.dart';
import '../../core/models/support_thread.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/support_api.dart';
import '../../core/utils/date_time_formatter.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  String _category = 'GENERAL';
  SupportThread? _thread;
  List<SupportMessage> _messages = const <SupportMessage>[];

  final List<_SupportTopic> _topics = const [
    _SupportTopic(
      category: 'SAFETY',
      label: 'Safety concern',
      prompt: 'I need help with a safety concern.',
      icon: Icons.shield_rounded,
    ),
    _SupportTopic(
      category: 'ACCOUNT',
      label: 'Account help',
      prompt: 'I need help with my account.',
      icon: Icons.person_rounded,
    ),
    _SupportTopic(
      category: 'TECHNICAL',
      label: 'App issue',
      prompt: 'Something is not working in the app.',
      icon: Icons.bug_report_rounded,
    ),
    _SupportTopic(
      category: 'REPORT',
      label: 'Report problem',
      prompt: 'I want to report something that happened.',
      icon: Icons.flag_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.on('support:message', _handleRealtimeMessage);
    RealtimeService.instance.on('support:updated', _handleSupportUpdated);
    _loadThread();
  }

  @override
  void dispose() {
    RealtimeService.instance.off('support:message', _handleRealtimeMessage);
    RealtimeService.instance.off('support:updated', _handleSupportUpdated);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    setState(() => _isLoading = true);

    try {
      final SupportConversation conversation = await SupportApi.instance
          .getThread();

      if (!mounted) {
        return;
      }

      setState(() {
        _thread = conversation.thread;
        _category = conversation.thread.category;
        _messages = conversation.messages;
      });
      _scrollToBottom();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage({String? prompt}) async {
    final String content = (prompt ?? _controller.text).trim();
    if (content.isEmpty || _isSending) {
      return;
    }

    setState(() => _isSending = true);

    try {
      final SupportMessage message = await SupportApi.instance.sendMessage(
        content: content,
        subject: _subjectForCategory(_category),
        category: _category,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = _appendMessage(_messages, message);
        _controller.clear();
      });
      _scrollToBottom();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _resolveThread() async {
    final SupportThread? thread = _thread;
    if (thread == null || thread.status == 'RESOLVED') {
      return;
    }

    try {
      final SupportThread updated = await SupportApi.instance.resolveThread(
        thread.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => _thread = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support request marked as resolved.')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _handleRealtimeMessage(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final dynamic rawThread = payload['thread'];
    final dynamic rawMessage = payload['message'];
    if (rawThread is Map) {
      final SupportThread thread = SupportThread.fromJson(
        Map<String, dynamic>.from(rawThread),
      );
      if (_thread != null && thread.id != _thread!.id) {
        return;
      }
      setState(() => _thread = thread);
    }

    if (rawMessage is! Map || !mounted) {
      return;
    }

    final SupportMessage message = SupportMessage.fromJson(
      Map<String, dynamic>.from(rawMessage),
    );
    if (_thread != null && message.threadId != _thread!.id) {
      return;
    }

    setState(() => _messages = _appendMessage(_messages, message));
    _scrollToBottom();
  }

  void _handleSupportUpdated(dynamic payload) {
    if (payload is! Map || payload['thread'] is! Map || !mounted) {
      return;
    }

    final SupportThread thread = SupportThread.fromJson(
      Map<String, dynamic>.from(payload['thread'] as Map),
    );
    if (_thread != null && thread.id != _thread!.id) {
      return;
    }
    setState(() => _thread = thread);
  }

  List<SupportMessage> _appendMessage(
    List<SupportMessage> messages,
    SupportMessage message,
  ) {
    if (messages.any((item) => item.id == message.id)) {
      return messages;
    }
    return <SupportMessage>[...messages, message];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _subjectForCategory(String category) {
    switch (category) {
      case 'SAFETY':
        return 'Safety concern';
      case 'ACCOUNT':
        return 'Account help';
      case 'TECHNICAL':
        return 'Technical issue';
      case 'REPORT':
        return 'Problem report';
      default:
        return 'Support request';
    }
  }

  @override
  Widget build(BuildContext context) {
    final SupportThread? thread = _thread;
    final bool resolved = thread?.status == 'RESOLVED';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text('Admin support'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: resolved ? null : _resolveThread,
            child: const Text('Resolve'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _SupportIntro(status: thread?.status ?? 'OPEN'),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _topics.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final _SupportTopic topic = _topics[index];
                      return _TopicButton(
                        topic: topic,
                        selected: _category == topic.category,
                        onTap: () {
                          setState(() => _category = topic.category);
                          if (_controller.text.trim().isEmpty) {
                            _controller.text = topic.prompt;
                          }
                        },
                      );
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final SupportMessage message = _messages[index];
                      return _SupportBubble(
                        message: message,
                        isMine: message.senderRole == 'USER',
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !resolved && !_isSending,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Write a message to admin...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        backgroundColor: const Color(0xFF33B8FF),
                        child: IconButton(
                          onPressed: resolved || _isSending
                              ? null
                              : _sendMessage,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SupportIntro extends StatelessWidget {
  const _SupportIntro({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE8FF)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFE59E),
            child: Icon(Icons.support_agent_rounded, color: Color(0xFF1A3D7C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need help from an admin?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ask about safety, account issues, app bugs, or anything that feels uncomfortable. Status: $status',
                  style: const TextStyle(color: Color(0xFF5A74A6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicButton extends StatelessWidget {
  const _TopicButton({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final _SupportTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE9F5FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF33B8FF) : const Color(0xFFDCE8FF),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(topic.icon, color: const Color(0xFF33B8FF)),
            const SizedBox(height: 8),
            Text(
              topic.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportBubble extends StatelessWidget {
  const _SupportBubble({required this.message, required this.isMine});

  final SupportMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF33B8FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMine ? 'You' : 'Admin',
                  style: TextStyle(
                    color: isMine ? Colors.white70 : const Color(0xFF7A8BBF),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                if (DateTimeFormatter.format(message.createdAt).isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    DateTimeFormatter.format(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.85)
                          : const Color(0xFF7A8BBF),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.content,
              style: TextStyle(
                color: isMine ? Colors.white : const Color(0xFF1A3D7C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportTopic {
  const _SupportTopic({
    required this.category,
    required this.label,
    required this.prompt,
    required this.icon,
  });

  final String category;
  final String label;
  final String prompt;
  final IconData icon;
}
