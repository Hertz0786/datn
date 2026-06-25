import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_summary.dart';
import '../../core/models/feed_post.dart';
import '../../core/models/media_asset.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/media_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../features/call/widgets/call_action_buttons.dart';
import '../../features/feed/post_detail_screen.dart';
import '../../shared/widgets/media_preview_grid.dart';
import '../../shared/widgets/skeleton_views.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/voice_recorder_widget.dart';
import 'sticker_picker_screen.dart';
import 'moderation_alert_dialog.dart';
import 'widgets/call_banner.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    this.chatId,
    this.title = 'Chat',
    this.avatarUrl = '',
    this.avatarLabel = '?',
    this.isGroup = false,
    this.isSocialGroup = false,
    this.members = const <PublicUser>[],
    this.createdBy = '',
  });

  final String? chatId;
  final String title;
  final String avatarUrl;
  final String avatarLabel;
  final bool isGroup;
  final bool isSocialGroup;
  final List<PublicUser> members;
  final String createdBy;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedMedia = <XFile>[];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isUpdatingGroup = false;

  List<ChatMessage> _messages = const <ChatMessage>[];
  late String _title;
  late String _avatarUrl;
  late List<PublicUser> _members;
  late String _createdBy;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _avatarUrl = widget.avatarUrl;
    _members = widget.members;
    _createdBy = widget.createdBy;
    _loadMessages();
    _listenRealtime();
  }

  String get _myId => (AuthSession.instance.user?['id'] ?? '').toString();

  String? get _otherParticipantId {
    final List<PublicUser> others = _members
        .where((user) => user.id != _myId)
        .toList();
    return others.isNotEmpty ? others.first.id : null;
  }

  bool get _isGroupOwner =>
      widget.isGroup &&
      !widget.isSocialGroup &&
      _createdBy.isNotEmpty &&
      _createdBy == _myId;

  @override
  void dispose() {
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      RealtimeService.instance.emit('chat:leave', widget.chatId);
    }
    RealtimeService.instance.off('chat:message', _handleRealtimeMessage);
    RealtimeService.instance.off(
      'chat:message_updated',
      _handleRealtimeMessageUpdated,
    );
    _messageController.dispose();
    super.dispose();
  }

  void _listenRealtime() {
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      RealtimeService.instance.emit('chat:join', widget.chatId);
      RealtimeService.instance.on('chat:message', _handleRealtimeMessage);
      RealtimeService.instance.on(
        'chat:message_updated',
        _handleRealtimeMessageUpdated,
      );
    }
  }

  Future<void> _loadMessages() async {
    if (widget.chatId == null || widget.chatId!.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final MessagesPage page = await ChatsApi.instance.listMessages(
        widget.chatId!,
      );

      if (!mounted) {
        return;
      }

      setState(() => _messages = page.items);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      await _handleApiError(error);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage({String? voicePath}) async {
    final String content = _messageController.text.trim();
    if ((content.isEmpty && _pickedMedia.isEmpty && (voicePath == null || voicePath.isEmpty)) ||
        _isSending) {
      return;
    }

    if (widget.chatId == null || widget.chatId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This chat is not connected yet.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final List<MediaAsset> uploadedMedia = <MediaAsset>[];
      for (final XFile file in _pickedMedia) {
        uploadedMedia.add(await MediaApi.instance.upload(filePath: file.path));
      }
      final List<String> mediaUrls = uploadedMedia
          .map((media) => media.url)
          .where((url) => url.isNotEmpty)
          .toList();

      String? uploadedVoiceUrl;
      if (voicePath != null && voicePath.isNotEmpty) {
        final MediaAsset voiceAsset = await MediaApi.instance.upload(
          filePath: voicePath,
          sourceType: 'VOICE',
        );
        uploadedVoiceUrl = voiceAsset.url;
      }

      final ChatMessage sent = await ChatsApi.instance.sendMessage(
        chatId: widget.chatId!,
        content: content,
        mediaUrls: mediaUrls,
        voiceUrl: uploadedVoiceUrl ?? '',
      );

      for (final MediaAsset media in uploadedMedia) {
        await MediaApi.instance.updateSource(
          mediaId: media.id,
          sourceType: 'MESSAGE',
          sourceId: sent.id,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = _appendMessage(_messages, sent);
        _messageController.clear();
        _pickedMedia.clear();
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      await _handleApiError(error);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _handleApiError(ApiException error) async {
    if (error.code == 'CONTENT_BLOCKED') {
      final List<String> categories = _extractCategories(error.details);
      final bool keepEditing = await ModerationAlertDialog.show(
        context: context,
        categories: categories,
        originalText: _messageController.text,
      );

      if (!mounted) {
        return;
      }

      if (!keepEditing) {
        setState(() => _messageController.clear());
      }
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }

  List<String> _extractCategories(Map<String, dynamic>? details) {
    if (details == null) {
      return const <String>[];
    }
    final dynamic raw = details['categories'];
    if (raw is List) {
      return raw
          .map((dynamic c) => c.toString())
          .where((String c) => c.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  Future<void> _pickMedia({required bool video}) async {
    if (_pickedMedia.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can attach up to 3 files per message.'),
        ),
      );
      return;
    }

    final XFile? file = video
        ? await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 2),
          )
        : await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
          );
    if (file == null) {
      return;
    }

    setState(() => _pickedMedia.add(file));
  }

  void _handleRealtimeMessage(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final String chatId = (payload['chatId'] ?? '').toString();
    if (chatId != widget.chatId) {
      return;
    }

    final dynamic rawMessage = payload['message'];
    if (rawMessage is! Map) {
      return;
    }

    final ChatMessage message = ChatMessage.fromJson(
      Map<String, dynamic>.from(rawMessage),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _messages = _appendMessage(_messages, message);
    });
  }

  void _handleRealtimeMessageUpdated(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final String chatId = (payload['chatId'] ?? '').toString();
    if (chatId != widget.chatId) {
      return;
    }

    final dynamic rawMessage = payload['message'];
    if (rawMessage is! Map) {
      return;
    }

    final ChatMessage message = ChatMessage.fromJson(
      Map<String, dynamic>.from(rawMessage),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _messages = _messages
          .map((item) => item.id == message.id ? message : item)
          .toList();
    });
  }

  List<ChatMessage> _appendMessage(
    List<ChatMessage> messages,
    ChatMessage message,
  ) {
    if (messages.any((item) => item.id == message.id)) {
      return messages;
    }
    return <ChatMessage>[...messages, message];
  }

  void _applyGroupSummary(ChatSummary chat) {
    setState(() {
      _title = chat.title.trim().isNotEmpty ? chat.title : _title;
      _avatarUrl = chat.avatarUrl;
      _members = chat.memberUsers;
      _createdBy = chat.createdBy;
    });
  }

  Future<void> _editGroupChat() async {
    if (!widget.isGroup || !_isGroupOwner || widget.chatId == null) {
      return;
    }

    final TextEditingController titleController = TextEditingController(
      text: _title,
    );
    final TextEditingController avatarController = TextEditingController(
      text: _avatarUrl,
    );

    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit group chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              TextField(
                controller: avatarController,
                decoration: const InputDecoration(labelText: 'Avatar URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final String title = titleController.text.trim();
    final String avatarUrl = avatarController.text.trim();
    titleController.dispose();
    avatarController.dispose();

    if (shouldSave != true) {
      return;
    }
    if (title.isEmpty) {
      _showSnack('Group name is required.');
      return;
    }

    await _updateGroupChat(title: title, avatarUrl: avatarUrl);
  }

  Future<void> _uploadGroupAvatar() async {
    if (!widget.isGroup || !_isGroupOwner || widget.chatId == null) {
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
    );
    if (image == null) {
      return;
    }

    setState(() => _isUpdatingGroup = true);
    try {
      final MediaAsset media = await MediaApi.instance.upload(
        filePath: image.path,
        sourceType: 'OTHER',
      );
      await _updateGroupChat(avatarUrl: media.url, showLoading: false);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Upload group avatar failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingGroup = false);
      }
    }
  }

  Future<void> _updateGroupChat({
    String? title,
    String? avatarUrl,
    bool showLoading = true,
  }) async {
    if (widget.chatId == null || widget.chatId!.isEmpty) {
      return;
    }
    if (showLoading) {
      setState(() => _isUpdatingGroup = true);
    }
    try {
      final ChatSummary chat = await ChatsApi.instance.updateGroupChat(
        chatId: widget.chatId!,
        title: title,
        avatarUrl: avatarUrl,
      );
      if (!mounted) {
        return;
      }
      _applyGroupSummary(chat);
      _showSnack('Group chat updated.');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Update group chat failed: $error');
    } finally {
      if (mounted && showLoading) {
        setState(() => _isUpdatingGroup = false);
      }
    }
  }

  Future<void> _addMembers() async {
    if (!widget.isGroup || !_isGroupOwner || widget.chatId == null) {
      return;
    }

    try {
      final FriendsPage page = await FriendsApi.instance.listFriends(limit: 50);
      if (!mounted) {
        return;
      }
      final Set<String> existingIds = _members
          .map((PublicUser user) => user.id)
          .toSet();
      final List<PublicUser> candidates = page.items
          .where((PublicUser user) => !existingIds.contains(user.id))
          .toList();
      if (candidates.isEmpty) {
        _showSnack('No friends available to add.');
        return;
      }

      final List<String>? selectedIds = await showDialog<List<String>>(
        context: context,
        builder: (_) => _AddMembersDialog(candidates: candidates),
      );
      if (selectedIds == null || selectedIds.isEmpty || !mounted) {
        return;
      }

      setState(() => _isUpdatingGroup = true);
      final ChatSummary chat = await ChatsApi.instance.addGroupMembers(
        chatId: widget.chatId!,
        memberIds: selectedIds,
      );
      if (!mounted) {
        return;
      }
      _applyGroupSummary(chat);
      _showSnack('Members added.');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Add members failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingGroup = false);
      }
    }
  }

  Future<void> _removeMember(PublicUser user) async {
    if (!widget.isGroup || widget.chatId == null || user.id.isEmpty) {
      return;
    }
    if (widget.isSocialGroup) {
      return;
    }
    final bool removingSelf = user.id == _myId;
    if (!removingSelf && !_isGroupOwner) {
      return;
    }

    final String name = user.displayName.trim().isNotEmpty
        ? user.displayName
        : user.username;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(removingSelf ? 'Leave group chat' : 'Remove member'),
        content: Text(
          removingSelf
              ? 'Leave $_title?'
              : 'Remove $name from this group chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(removingSelf ? 'Leave' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isUpdatingGroup = true);
    try {
      final ChatSummary chat = await ChatsApi.instance.removeGroupMember(
        chatId: widget.chatId!,
        userId: user.id,
      );
      if (!mounted) {
        return;
      }
      if (removingSelf) {
        Navigator.pop(context);
        return;
      }
      _applyGroupSummary(chat);
      _showSnack('Member removed.');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Remove member failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingGroup = false);
      }
    }
  }

  void _showGroupInfo() {
    if (!widget.isGroup) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return _GroupInfoSheet(
          title: _title,
          avatarUrl: _avatarUrl,
          avatarLabel: _groupInitials(_title),
          members: _members,
          isOwner: _isGroupOwner,
          isUpdating: _isUpdatingGroup,
          canLeave: !widget.isSocialGroup,
          currentUserId: _myId,
          onEdit: () {
            Navigator.pop(context);
            _editGroupChat();
          },
          onUploadAvatar: () {
            Navigator.pop(context);
            _uploadGroupAvatar();
          },
          onAddMembers: () {
            Navigator.pop(context);
            _addMembers();
          },
          onRemoveMember: (PublicUser user) {
            Navigator.pop(context);
            _removeMember(user);
          },
          onLeave: () {
            final PublicUser self = _members.firstWhere(
              (PublicUser user) => user.id == _myId,
              orElse: () => PublicUser(
                id: _myId,
                displayName: 'You',
                username: '',
                age: 0,
                role: 'CHILD',
                avatarUrl: '',
                bio: '',
                favoriteTopics: const <String>[],
              ),
            );
            Navigator.pop(context);
            _removeMember(self);
          },
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final String myId = _myId;
    final Map<String, PublicUser> usersById = <String, PublicUser>{
      for (final PublicUser user in _members) user.id: user,
    };

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.appHeading),
        title: Row(
          children: [
            UserAvatar(
              avatarUrl: _avatarUrl,
              initials: widget.isGroup
                  ? _groupInitials(_title)
                  : widget.avatarLabel,
              radius: 16,
              backgroundColor: widget.isGroup
                  ? const Color(0xFFD8C9FF)
                  : const Color(0xFFBEEAFF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.appHeading,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.isGroup)
            CallActionButtons(
              calleeId: _otherParticipantId ?? '',
              compact: true,
            ),
          if (widget.isGroup)
            IconButton(
              onPressed: _showGroupInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const _ChatSkeletonList()
                : RefreshIndicator(
                    onRefresh: _loadMessages,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final ChatMessage message = _messages[index];
                        if (message.isCallBanner) {
                          // Call-summary messages are system events: render as
                          // a centered banner and skip the regular bubble.
                          final bool callFromMe =
                              message.callMeta?.initiatorId == myId;
                          return CallBanner(
                            message: message,
                            isOutgoing: callFromMe,
                          );
                        }
                        final bool isMe =
                            message.senderId == myId ||
                            message.senderId == 'local';
                        return _Bubble(
                          isMe: isMe,
                          message: message,
                          senderName: widget.isGroup && !isMe
                              ? _senderName(usersById[message.senderId])
                              : '',
                        );
                      },
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            color: context.appSurface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pickedMedia.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final XFile file in _pickedMedia)
                          Chip(
                            label: Text(file.name),
                            onDeleted: _isSending
                                ? null
                                : () =>
                                      setState(() => _pickedMedia.remove(file)),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _isSending
                          ? null
                          : () async {
                              final String? code = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const StickerPickerScreen(),
                                ),
                              );
                              if (code == null || code.isEmpty || !mounted) {
                                return;
                              }
                              setState(() {
                                _messageController.text = code;
                              });
                              await _sendMessage();
                            },
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      color: const Color(0xFF33B8FF),
                    ),
                    IconButton(
                      onPressed: _isSending
                          ? null
                          : () => _pickMedia(video: false),
                      icon: const Icon(Icons.photo_library_rounded),
                      color: const Color(0xFF33B8FF),
                    ),
                    IconButton(
                      onPressed: _isSending
                          ? null
                          : () => _pickMedia(video: true),
                      icon: const Icon(Icons.video_library_rounded),
                      color: const Color(0xFF7A5CFF),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          filled: true,
                          fillColor: context.appChip,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    VoiceRecorderWidget(
                      compact: true,
                      onUploading: () {
                        if (mounted) {
                          setState(() => _isSending = true);
                        }
                      },
                      onRecorded: (path, _) {
                        _sendMessage(voicePath: path);
                      },
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFFF9AD5),
                      child: IconButton(
                        onPressed: _sendMessage,
                        icon: _isSending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _senderName(PublicUser? user) {
    if (user == null) {
      return 'Member';
    }
    return user.displayName.trim().isNotEmpty
        ? user.displayName
        : user.username;
  }

  String _groupInitials(String title) {
    final List<String> parts = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'GC';
    }
    if (parts.length == 1) {
      final String first = parts.first;
      return first.length >= 2
          ? first.substring(0, 2).toUpperCase()
          : first.toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.isMe,
    required this.message,
    this.senderName = '',
  });

  final bool isMe;
  final ChatMessage message;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF33B8FF) : context.appSurface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (senderName.isNotEmpty) ...[
              Text(
                senderName,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7A8BBF),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (message.content.isNotEmpty)
              _MessageContent(content: message.content, isMe: isMe),
            if (message.voiceUrl.isNotEmpty) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 6),
              _VoiceMessageBubble(voiceUrl: message.voiceUrl, isMe: isMe),
            ],
            if (message.isPostShare && message.postId != null) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 6),
              _SharedPostCard(postId: message.postId!, isMe: isMe),
            ],
            if (message.mediaUrls.isNotEmpty) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 8),
              SizedBox(
                width: 220,
                child: MediaPreviewGrid(urls: message.mediaUrls, compact: true),
              ),
            ],
            if (DateTimeFormatter.format(message.createdAt).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                DateTimeFormatter.format(message.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.85)
                      : context.appMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupInfoSheet extends StatelessWidget {
  const _GroupInfoSheet({
    required this.title,
    required this.avatarUrl,
    required this.avatarLabel,
    required this.members,
    required this.isOwner,
    required this.isUpdating,
    required this.canLeave,
    required this.currentUserId,
    required this.onEdit,
    required this.onUploadAvatar,
    required this.onAddMembers,
    required this.onRemoveMember,
    required this.onLeave,
  });

  final String title;
  final String avatarUrl;
  final String avatarLabel;
  final List<PublicUser> members;
  final bool isOwner;
  final bool isUpdating;
  final bool canLeave;
  final String currentUserId;
  final VoidCallback onEdit;
  final VoidCallback onUploadAvatar;
  final VoidCallback onAddMembers;
  final ValueChanged<PublicUser> onRemoveMember;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  avatarUrl: avatarUrl,
                  initials: avatarLabel,
                  radius: 28,
                  backgroundColor: const Color(0xFFD8C9FF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                      Text(
                        '${members.length} members',
                        style: const TextStyle(color: Color(0xFF7A8BBF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isOwner) ...[
                  ActionChip(
                    avatar: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                    onPressed: isUpdating ? null : onEdit,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Avatar'),
                    onPressed: isUpdating ? null : onUploadAvatar,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add'),
                    onPressed: isUpdating ? null : onAddMembers,
                  ),
                ],
                if (canLeave)
                  ActionChip(
                    avatar: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Leave'),
                    onPressed: isUpdating ? null : onLeave,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Members',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A3D7C),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: members.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final PublicUser user = members[index];
                  final bool isMe = user.id == currentUserId;
                  final String name = user.displayName.trim().isNotEmpty
                      ? user.displayName
                      : user.username;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      avatarUrl: user.avatarUrl,
                      initials: user.initials,
                      radius: 18,
                      backgroundColor: const Color(0xFFBEEAFF),
                      lastActiveAt: user.lastActiveAt,
                    ),
                    title: Text(
                      isMe ? '$name (you)' : name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('@${user.username}'),
                    trailing: isOwner && !isMe
                        ? IconButton(
                            onPressed: isUpdating
                                ? null
                                : () => onRemoveMember(user),
                            icon: const Icon(
                              Icons.person_remove_rounded,
                              color: Color(0xFFE05A78),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({required this.candidates});

  final List<PublicUser> candidates;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add members'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.candidates.length,
          itemBuilder: (context, index) {
            final PublicUser friend = widget.candidates[index];
            final bool selected = _selectedIds.contains(friend.id);
            final String name = friend.displayName.trim().isNotEmpty
                ? friend.displayName
                : friend.username;
            return CheckboxListTile(
              value: selected,
              onChanged: (_) {
                setState(() {
                  if (selected) {
                    _selectedIds.remove(friend.id);
                  } else {
                    _selectedIds.add(friend.id);
                  }
                });
              },
              title: Text(name),
              subtitle: Text('@${friend.username}'),
              secondary: UserAvatar(
                avatarUrl: friend.avatarUrl,
                initials: friend.initials,
                radius: 18,
                backgroundColor: const Color(0xFFBEEAFF),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedIds.toList()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.content, required this.isMe});

  final String content;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final IconData? sticker = iconForSticker(content);
    if (sticker != null) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          sticker,
          size: 56,
          color: isMe ? Colors.white : const Color(0xFF33B8FF),
        ),
      );
    }

    return Text(
      content,
      style: TextStyle(color: isMe ? Colors.white : context.appHeading),
    );
  }
}

class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({required this.voiceUrl, required this.isMe});

  final String voiceUrl;
  final bool isMe;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
      });
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading || _error != null) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.audioSource != null) {
        await _player.play();
      } else {
        setState(() {
          _isLoading = true;
          _error = null;
        });
        try {
          await _player.setUrl(widget.voiceUrl);
          await _player.play();
        } catch (e) {
          if (mounted) {
            setState(() {
              _error = 'Cannot play audio';
            });
          }
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMe ? const Color(0xFF33B8FF) : Colors.white;
    final barColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF33B8FF).withValues(alpha: 0.3);
    final activeBarColor = widget.isMe ? Colors.white : const Color(0xFF33B8FF);
    final textColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF33B8FF);

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? Colors.white.withValues(alpha: 0.25)
            : const Color(0xFF33B8FF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFF33B8FF).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white : const Color(0xFF33B8FF),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: iconColor,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: _isPlaying ? 60 : 20,
                        height: 3,
                        decoration: BoxDecoration(
                          color: activeBarColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ?? (_isPlaying ? 'Playing...' : 'Voice message'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _error != null ? Colors.red.shade300 : textColor,
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

class _SharedPostCard extends StatefulWidget {
  const _SharedPostCard({required this.postId, required this.isMe});

  final String postId;
  final bool isMe;

  @override
  State<_SharedPostCard> createState() => _SharedPostCardState();
}

class _SharedPostCardState extends State<_SharedPostCard> {
  FeedPost? _post;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    try {
      final FeedPost post = await PostsApi.instance.getPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load post';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.25)
        : const Color(0xFFEFF7FF);
    final Color borderColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.4)
        : const Color(0xFFD7E7FF);
    final Color textColor = widget.isMe ? Colors.white : const Color(0xFF1A3D7C);
    final Color subColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.8)
        : const Color(0xFF7A8BBF);

    return GestureDetector(
      onTap: _post != null
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(initialPost: _post),
                ),
              );
            }
          : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: _isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Shared post...',
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                ],
              )
            : _error != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: subColor),
                      const SizedBox(width: 6),
                      Text(
                        'Shared post',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.article_outlined, size: 18, color: textColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _post!.authorDisplayName.isNotEmpty
                                  ? _post!.authorDisplayName
                                  : _post!.authorUsername,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _post!.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      if (_post!.mediaUrls.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: const Color(0xFFE8F4FF),
                          ),
                          child: const Icon(
                            Icons.image_rounded,
                            color: Color(0xFF33B8FF),
                            size: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _ChatSkeletonList extends StatelessWidget {
  const _ChatSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        ChatMessageSkeleton(isMe: false),
        ChatMessageSkeleton(isMe: true),
        ChatMessageSkeleton(isMe: false),
        ChatMessageSkeleton(isMe: false),
        ChatMessageSkeleton(isMe: true),
        ChatMessageSkeleton(isMe: true),
      ],
    );
  }
}
