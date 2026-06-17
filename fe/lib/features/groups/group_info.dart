import 'package:flutter/material.dart';

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.topic,
    required this.description,
    required this.ownerId,
    required this.avatarUrl,
    required this.memberCount,
    required this.minAge,
    required this.maxAge,
    required this.icon,
    required this.color,
    required this.dailyMission,
  });

  final String id;
  final String name;
  final String topic;
  final String description;
  final String ownerId;
  final String avatarUrl;
  final int memberCount;
  final int minAge;
  final int maxAge;
  final IconData icon;
  final Color color;
  final String dailyMission;

  factory GroupInfo.fromJson(Map<String, dynamic> json) {
    final String topic = (json['topic'] ?? 'General').toString();
    final dynamic ownerRaw = json['ownerId'];
    final String ownerId = ownerRaw is Map<String, dynamic>
        ? (ownerRaw['_id'] ?? ownerRaw['id'] ?? '').toString()
        : (ownerRaw ?? '').toString();

    return GroupInfo(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      topic: topic,
      description: (json['description'] ?? '').toString(),
      ownerId: ownerId,
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      minAge: (json['ageMin'] as num?)?.toInt() ?? 7,
      maxAge: (json['ageMax'] as num?)?.toInt() ?? 14,
      icon: _iconForTopic(topic),
      color: _colorForTopic(topic),
      dailyMission: 'Share something fun about $topic today.',
    );
  }

  GroupInfo copyWith({
    String? id,
    String? name,
    String? topic,
    String? description,
    String? ownerId,
    String? avatarUrl,
    int? memberCount,
    int? minAge,
    int? maxAge,
    IconData? icon,
    Color? color,
    String? dailyMission,
  }) {
    return GroupInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      topic: topic ?? this.topic,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      memberCount: memberCount ?? this.memberCount,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      dailyMission: dailyMission ?? this.dailyMission,
    );
  }

  static IconData _iconForTopic(String topic) {
    switch (topic.toLowerCase()) {
      case 'drawing':
        return Icons.palette_rounded;
      case 'science':
        return Icons.rocket_launch_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'coding':
        return Icons.code_rounded;
      case 'sports':
        return Icons.sports_soccer_rounded;
      default:
        return Icons.groups_rounded;
    }
  }

  static Color _colorForTopic(String topic) {
    switch (topic.toLowerCase()) {
      case 'drawing':
        return const Color(0xFFFFC5E6);
      case 'science':
        return const Color(0xFF9BE7FF);
      case 'music':
        return const Color(0xFFFFE59E);
      case 'coding':
        return const Color(0xFFBEEBD0);
      default:
        return const Color(0xFFD8C9FF);
    }
  }
}
