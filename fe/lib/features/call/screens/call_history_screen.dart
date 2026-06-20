import 'package:flutter/material.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../models/call_history_item.dart';
import '../services/call_api.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final ScrollController _controller = ScrollController();
  final List<CallHistoryItem> _items = <CallHistoryItem>[];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (_controller.position.pixels >
        _controller.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final CallHistoryPage page = await CallApi.instance.listHistory();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _items.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final CallHistoryPage page = await CallApi.instance.listHistory(
        before: _items.last.id,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // Silent: user can scroll again to retry.
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent calls'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _items.isEmpty) {
      return _ErrorState(
        message: _errorMessage!,
        onRetry: _loadInitial,
      );
    }
    if (_items.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      controller: _controller,
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _CallHistoryTile(item: _items[index]);
      },
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({required this.item});

  final CallHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final IconData icon = item.isVideo ? Icons.videocam : Icons.call;
    final Color color = _directionColor(item.direction);
    return ListTile(
      leading: Stack(
        children: <Widget>[
          UserAvatar(
            avatarUrl: item.otherUser.avatarUrl,
            initials: item.otherUser.initials,
            radius: 24,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 14),
            ),
          ),
        ],
      ),
      title: Text(
        item.otherUser.displayName.isNotEmpty
            ? item.otherUser.displayName
            : item.otherUser.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_subtitle()),
      trailing: Text(
        _formatDate(item.startedAt),
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }

  String _subtitle() {
    final String label = _directionLabel(item.direction);
    if (item.direction == CallDirection.missed) {
      return '$label ${item.isVideo ? 'video' : 'voice'} call';
    }
    if (item.durationSeconds > 0) {
      final String dur = _formatDuration(item.durationSeconds);
      return '$label • $dur';
    }
    return '$label ${item.isVideo ? 'video' : 'voice'} call';
  }

  String _directionLabel(CallDirection direction) {
    switch (direction) {
      case CallDirection.incoming:
        return 'Incoming';
      case CallDirection.outgoing:
        return 'Outgoing';
      case CallDirection.missed:
        return 'Missed';
    }
  }

  Color _directionColor(CallDirection direction) {
    switch (direction) {
      case CallDirection.incoming:
        return Colors.blueAccent;
      case CallDirection.outgoing:
        return Colors.green;
      case CallDirection.missed:
        return Colors.redAccent;
    }
  }

  String _formatDate(DateTime date) {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(date);
    if (diff.inDays > 6) {
      return '${date.day}/${date.month}';
    }
    if (diff.inDays >= 1) {
      return '${diff.inDays}d';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours}h';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes}m';
    }
    return 'now';
  }

  String _formatDuration(int seconds) {
    final String mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final String ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const <Widget>[
        SizedBox(height: 120),
        Icon(Icons.call_outlined, size: 72, color: Colors.black26),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No calls yet',
            style: TextStyle(fontSize: 18, color: Colors.black54),
          ),
        ),
        SizedBox(height: 6),
        Center(
          child: Text(
            'Calls you make or receive will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}
