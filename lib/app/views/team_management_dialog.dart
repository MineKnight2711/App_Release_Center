import 'dart:async';

import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

Future<void> showTeamManagementDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _TeamManagementDialog(),
  );
}

class _TeamManagementDialog extends StatefulWidget {
  const _TeamManagementDialog();

  @override
  State<_TeamManagementDialog> createState() => _TeamManagementDialogState();
}

class _TeamManagementDialogState extends State<_TeamManagementDialog> {
  var _members = <TeamMemberProfile>[];
  CreatedTeamInvite? _invite;
  TeamRole _inviteRole = TeamRole.dev;
  var _isLoading = true;
  var _isCreatingInvite = false;
  var _error = '';

  AuthService get _auth => Get.find<AuthService>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadMembers());
  }

  @override
  Widget build(BuildContext context) {
    final profile = _auth.profile.value;
    final isAdmin = profile?.canManageTeam ?? false;

    return AlertDialog(
      key: const Key('team-management-dialog'),
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          const Icon(Icons.admin_panel_settings_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              profile?.teamName.isNotEmpty == true ? profile!.teamName : 'Team',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 660,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TeamChip(
                  icon: Icons.person_outline,
                  label: profile?.email ?? '',
                ),
                _TeamChip(
                  icon: Icons.verified_user_outlined,
                  label: profile?.role?.label ?? 'No role',
                  highlighted: isAdmin,
                ),
              ],
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              _TeamMessage(message: _error, isError: true),
            ],
            if (_invite != null) ...[
              const SizedBox(height: 12),
              _InviteCodePanel(invite: _invite!),
            ],
            const SizedBox(height: 14),
            if (isAdmin) _buildInviteControls(),
            if (isAdmin) const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                  ? const Center(child: Text('No members yet.'))
                  : ListView.separated(
                      itemCount: _members.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _buildMemberRow(_members[index], isAdmin);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_outlined),
          label: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInviteControls() {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<TeamRole>(
            key: ValueKey('invite-role-${_inviteRole.value}'),
            initialValue: _inviteRole,
            decoration: const InputDecoration(
              labelText: 'Invite role',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
            items: TeamRole.values
                .map(
                  (role) =>
                      DropdownMenuItem(value: role, child: Text(role.label)),
                )
                .toList(),
            onChanged: _isCreatingInvite
                ? null
                : (value) =>
                      setState(() => _inviteRole = value ?? TeamRole.dev),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          key: const Key('create-team-invite'),
          onPressed: _isCreatingInvite ? null : _createInvite,
          icon: _isCreatingInvite
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_email_unread_outlined),
          label: const Text('Create invite'),
        ),
      ],
    );
  }

  Widget _buildMemberRow(TeamMemberProfile member, bool isAdmin) {
    final currentUid = _auth.profile.value?.uid;
    final isSelf = member.uid == currentUid;
    final title = member.displayName.trim().isEmpty
        ? member.email
        : member.displayName;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: AppCyberTheme.gridShellDecoration(active: isSelf),
      child: Row(
        children: [
          Icon(
            isSelf ? Icons.person_pin_outlined : Icons.person_outline,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? member.uid : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 12,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 128,
            child: DropdownButtonFormField<TeamRole>(
              key: ValueKey('member-role-${member.uid}-${member.role.value}'),
              initialValue: member.role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              items: TeamRole.values
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.label)),
                  )
                  .toList(),
              onChanged: !isAdmin || isSelf
                  ? null
                  : (role) {
                      if (role != null) {
                        unawaited(_updateRole(member.uid, role));
                      }
                    },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Remove member',
            onPressed: !isAdmin || isSelf
                ? null
                : () => unawaited(_removeMember(member.uid)),
            icon: const Icon(Icons.person_remove_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final members = await _auth.listMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createInvite() async {
    setState(() {
      _isCreatingInvite = true;
      _error = '';
    });
    try {
      final invite = await _auth.createInvite(role: _inviteRole);
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  Future<void> _updateRole(String uid, TeamRole role) async {
    try {
      await _auth.updateMemberRole(uid: uid, role: role);
      await _loadMembers();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _removeMember(String uid) async {
    try {
      await _auth.removeMember(uid);
      await _loadMembers();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }
}

class _InviteCodePanel extends StatelessWidget {
  const _InviteCodePanel({required this.invite});

  final CreatedTeamInvite invite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppCyberTheme.neonGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppCyberTheme.neonGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.vpn_key_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              invite.code,
              style: AppCyberTheme.dataTextStyle(
                size: 11.4,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy invite code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppCyberTheme.neonGreen
        : AppCyberTheme.electricBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppCyberTheme.dataTextStyle(
              size: 10.8,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMessage extends StatelessWidget {
  const _TeamMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : AppCyberTheme.electricBlue;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: AppCyberTheme.dataTextStyle(
          size: 11.2,
          color: AppCyberTheme.textPrimary,
        ),
      ),
    );
  }
}
