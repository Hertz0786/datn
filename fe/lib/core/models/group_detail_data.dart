import '../../features/groups/group_info.dart';
import 'public_user.dart';

class GroupDetailData {
  const GroupDetailData({
    required this.group,
    required this.members,
    required this.pendingMembers,
    required this.isJoined,
    required this.isPending,
  });

  final GroupInfo group;
  final List<PublicUser> members;
  final List<PublicUser> pendingMembers;
  final bool isJoined;
  final bool isPending;
}
