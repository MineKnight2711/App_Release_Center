import 'dart:async';

import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum _AuthPanelMode { signIn, register }

enum _RegisterTarget { createTeam, joinInvite }

class LoginView extends StatefulWidget {
  const LoginView({super.key, required this.firebaseConfigured});

  final bool firebaseConfigured;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _teamNameController = TextEditingController(text: 'Release Team');
  final _inviteCodeController = TextEditingController();

  var _mode = _AuthPanelMode.signIn;
  var _registerTarget = _RegisterTarget.createTeam;
  var _obscurePassword = true;
  var _localError = '';

  AuthService get _auth => Get.find<AuthService>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _teamNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppCyberTheme.backdropGradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _buildPanel(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Container(
      decoration: AppCyberTheme.panelDecoration(active: true),
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppCyberTheme.electricBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppCyberTheme.electricBlue.withValues(alpha: 0.44),
                  ),
                ),
                child: const SizedBox.square(
                  dimension: 42,
                  child: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Release Center',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in with your team account.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!widget.firebaseConfigured) ...[
            const _AuthMessage(
              icon: Icons.warning_amber_outlined,
              message:
                  'Firebase is not configured. Add Firebase values to .env, then reopen the app.',
            ),
          ] else ...[
            SegmentedButton<_AuthPanelMode>(
              segments: const [
                ButtonSegment(
                  value: _AuthPanelMode.signIn,
                  icon: Icon(Icons.login_outlined),
                  label: Text('Login'),
                ),
                ButtonSegment(
                  value: _AuthPanelMode.register,
                  icon: Icon(Icons.person_add_alt_outlined),
                  label: Text('Register'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) {
                setState(() {
                  _mode = value.first;
                  _localError = '';
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('auth-email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('auth-password'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.password_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_mode == _AuthPanelMode.register) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('auth-display-name'),
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_RegisterTarget>(
                segments: const [
                  ButtonSegment(
                    value: _RegisterTarget.createTeam,
                    icon: Icon(Icons.group_add_outlined),
                    label: Text('Create team'),
                  ),
                  ButtonSegment(
                    value: _RegisterTarget.joinInvite,
                    icon: Icon(Icons.mark_email_unread_outlined),
                    label: Text('Join invite'),
                  ),
                ],
                selected: {_registerTarget},
                onSelectionChanged: (value) {
                  setState(() {
                    _registerTarget = value.first;
                    _localError = '';
                  });
                },
              ),
              const SizedBox(height: 10),
              if (_registerTarget == _RegisterTarget.createTeam)
                TextField(
                  key: const Key('auth-team-name'),
                  controller: _teamNameController,
                  decoration: const InputDecoration(
                    labelText: 'Team name',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                )
              else
                TextField(
                  key: const Key('auth-invite-code'),
                  controller: _inviteCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
            ],
            const SizedBox(height: 12),
            Obx(() {
              final message = _localError.isNotEmpty
                  ? _localError
                  : _auth.authError.value;
              if (message.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AuthMessage(
                  icon: Icons.error_outline,
                  message: message,
                  isError: true,
                ),
              );
            }),
            Obx(
              () => FilledButton.icon(
                key: const Key('auth-submit'),
                onPressed: _auth.isBusy.value ? null : _submit,
                icon: _auth.isBusy.value
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _mode == _AuthPanelMode.signIn
                            ? Icons.login_outlined
                            : Icons.person_add_alt_outlined,
                      ),
                label: Text(
                  _mode == _AuthPanelMode.signIn ? 'Login' : 'Register',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _localError = 'Email and password are required.');
      return;
    }

    setState(() => _localError = '');
    try {
      if (_mode == _AuthPanelMode.signIn) {
        await _auth.signIn(email: email, password: password);
        return;
      }

      final displayName = _displayNameController.text.trim();
      if (_registerTarget == _RegisterTarget.createTeam) {
        final teamName = _teamNameController.text.trim();
        if (teamName.isEmpty) {
          setState(() => _localError = 'Team name is required.');
          return;
        }
        await _auth.registerWithNewTeam(
          email: email,
          password: password,
          displayName: displayName,
          teamName: teamName,
        );
      } else {
        final inviteCode = _inviteCodeController.text.trim();
        if (inviteCode.isEmpty) {
          setState(() => _localError = 'Invite code is required.');
          return;
        }
        await _auth.registerWithInvite(
          email: email,
          password: password,
          displayName: displayName,
          inviteCode: inviteCode,
        );
      }
    } on AuthServiceException {
      // AuthService owns the displayed error message.
    }
  }
}

class TeamSetupView extends StatefulWidget {
  const TeamSetupView({super.key});

  @override
  State<TeamSetupView> createState() => _TeamSetupViewState();
}

class _TeamSetupViewState extends State<TeamSetupView> {
  final _teamNameController = TextEditingController(text: 'Release Team');
  final _inviteCodeController = TextEditingController();
  var _target = _RegisterTarget.createTeam;
  var _localError = '';

  AuthService get _auth => Get.find<AuthService>();

  @override
  void dispose() {
    _teamNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _auth.profile.value;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppCyberTheme.backdropGradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Container(
                  decoration: AppCyberTheme.panelDecoration(active: true),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose a team',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile?.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<_RegisterTarget>(
                        segments: const [
                          ButtonSegment(
                            value: _RegisterTarget.createTeam,
                            icon: Icon(Icons.group_add_outlined),
                            label: Text('Create team'),
                          ),
                          ButtonSegment(
                            value: _RegisterTarget.joinInvite,
                            icon: Icon(Icons.mark_email_unread_outlined),
                            label: Text('Join invite'),
                          ),
                        ],
                        selected: {_target},
                        onSelectionChanged: (value) {
                          setState(() {
                            _target = value.first;
                            _localError = '';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_target == _RegisterTarget.createTeam)
                        TextField(
                          key: const Key('team-setup-name'),
                          controller: _teamNameController,
                          decoration: const InputDecoration(
                            labelText: 'Team name',
                            prefixIcon: Icon(Icons.groups_outlined),
                          ),
                        )
                      else
                        TextField(
                          key: const Key('team-setup-invite-code'),
                          controller: _inviteCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Invite code',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      const SizedBox(height: 12),
                      Obx(() {
                        final message = _localError.isNotEmpty
                            ? _localError
                            : _auth.authError.value;
                        if (message.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AuthMessage(
                            icon: Icons.error_outline,
                            message: message,
                            isError: true,
                          ),
                        );
                      }),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => unawaited(_auth.signOut()),
                              icon: const Icon(Icons.logout_outlined),
                              label: const Text('Logout'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Obx(
                              () => FilledButton.icon(
                                key: const Key('team-setup-submit'),
                                onPressed: _auth.isBusy.value ? null : _submit,
                                icon: _auth.isBusy.value
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_outlined),
                                label: const Text('Continue'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _localError = '');
    try {
      if (_target == _RegisterTarget.createTeam) {
        final teamName = _teamNameController.text.trim();
        if (teamName.isEmpty) {
          setState(() => _localError = 'Team name is required.');
          return;
        }
        await _auth.createTeamForCurrentUser(teamName);
      } else {
        final inviteCode = _inviteCodeController.text.trim();
        if (inviteCode.isEmpty) {
          setState(() => _localError = 'Invite code is required.');
          return;
        }
        await _auth.joinCurrentUserWithInvite(inviteCode);
      }
    } on AuthServiceException {
      // AuthService owns the displayed error message.
    }
  }
}

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppCyberTheme.dataTextStyle(
                size: 11.4,
                color: AppCyberTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
