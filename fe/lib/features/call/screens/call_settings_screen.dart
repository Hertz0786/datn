import 'package:flutter/material.dart';

import '../services/call_api.dart';

class CallSettingsScreen extends StatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  State<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<CallSettingsScreen> {
  CallSettingsModel? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Local mutable copies.
  String _whoCanCall = 'friends_only';
  Set<String> _allowedCallTypes = <String>{'voice', 'video'};
  int _maxCallDurationMinutes = 0;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final CallSettingsModel settings = await CallApi.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _whoCanCall = settings.whoCanCall;
        _allowedCallTypes = settings.allowedCallTypes.toSet();
        _maxCallDurationMinutes =
            (settings.maxCallDurationSeconds / 60).round();
        _notificationsEnabled = settings.notificationsEnabled;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final List<String> types = _allowedCallTypes.toList()..sort();
      final CallSettingsModel updated = await CallApi.instance.updateSettings(
        whoCanCall: _whoCanCall,
        allowedCallTypes: types,
        maxCallDurationSeconds: _maxCallDurationMinutes * 60,
        notificationsEnabled: _notificationsEnabled,
      );
      if (!mounted) return;
      setState(() {
        _settings = updated;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call settings'),
        actions: <Widget>[
          if (!_isLoading && _settings != null)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        const _SectionHeader('Who can call me'),
        RadioGroup<String>(
          groupValue: _whoCanCall,
          onChanged: (String? value) {
            if (value != null) setState(() => _whoCanCall = value);
          },
          child: Column(
            children: <Widget>[
              RadioListTile<String>(
                value: 'friends_only',
                title: const Text('Friends only'),
                subtitle:
                    const Text('Only people you have friended can call.'),
              ),
              RadioListTile<String>(
                value: 'everyone',
                title: const Text('Everyone'),
                subtitle: const Text('Anyone on Kiddo Social can call you.'),
              ),
              RadioListTile<String>(
                value: 'nobody',
                title: const Text('Nobody'),
                subtitle: const Text('Block all incoming calls.'),
              ),
            ],
          ),
        ),
        const Divider(),
        const _SectionHeader('Allowed call types'),
        CheckboxListTile(
          value: _allowedCallTypes.contains('voice'),
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                _allowedCallTypes.add('voice');
              } else {
                _allowedCallTypes.remove('voice');
              }
            });
          },
          title: const Text('Voice calls'),
        ),
        CheckboxListTile(
          value: _allowedCallTypes.contains('video'),
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                _allowedCallTypes.add('video');
              } else {
                _allowedCallTypes.remove('video');
              }
            });
          },
          title: const Text('Video calls'),
        ),
        const Divider(),
        const _SectionHeader('Max call duration'),
        ListTile(
          title: const Text('Auto-end after'),
          subtitle: Text(
            _maxCallDurationMinutes == 0
                ? 'No limit'
                : '$_maxCallDurationMinutes minutes',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _maxCallDurationMinutes.toDouble(),
            min: 0,
            max: 120,
            divisions: 24,
            label: _maxCallDurationMinutes == 0
                ? 'No limit'
                : '$_maxCallDurationMinutes min',
            onChanged: (double value) {
              setState(() => _maxCallDurationMinutes = value.round());
            },
          ),
        ),
        const Divider(),
        SwitchListTile(
          value: _notificationsEnabled,
          onChanged: (bool value) {
            setState(() => _notificationsEnabled = value);
          },
          title: const Text('Call notifications'),
          subtitle: const Text('Show an alert when you receive a call.'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
