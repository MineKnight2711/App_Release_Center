# Remote Windows Unlock

## Scope

Remote unlock is an optional Windows-only feature. It unlocks the currently
selected Windows account with that account's password. It does not support a
Windows Hello PIN, hibernation wake, or a powered-off machine.

The phone may remember that password so the account can be signed in with a
face or a fingerprint instead of typing it each time — see *Saved password on
the phone* below. The biometrics involved are the **phone's**, used to release
a stored password; Windows still receives a password, and Windows Hello is not
part of this.

Wake-on-LAN and remote unlock are separate steps:

1. Wake the machine and wait for Windows to reach the lock screen.
2. Submit the Windows account password from the paired mobile app.

## Architecture

The installer creates a non-exportable 3072-bit RSA key in the Local Machine
certificate store and registers the AMC Credential Provider. Only its public
modulus and exponent are exposed to the desktop app and paired mobile clients.

When Windows is locked, the desktop app publishes a random one-time challenge
with a three-minute lifetime. The mobile app packages the challenge, account,
password, and a 45-second expiry, then encrypts the package with RSA-OAEP and
SHA-256. The relay and desktop app receive only the ciphertext.

The Credential Provider runs in LogonUI. It decrypts the pending request with
the machine private key, verifies the account, challenge, and expiry, deletes
the request, and submits a protected interactive logon credential to Windows.
The password is not logged or persisted in plaintext.

## Which account is unlocked

The Credential Provider compares the account in the request against the SID of
the logon tile, not against its display name. The two names never agree on a
Microsoft-account machine — the tile calls the account
`MicrosoftAccount\someone@example.com` while the desktop app knows only the SAM
name `MACHINE\someone` — so a name comparison refused every unlock on Windows
11 Home. Both names resolve to one SID, and that is the identity the check is
about.

## Saved password on the phone

Remembering the password is off until it is turned on for one account on one
desktop, and it changes the threat model: a Windows password now sits on the
phone. Four rules pay for that, and all four are enforced in
`RemoteUnlockSessionService` rather than at the call sites, because a bypass
anywhere would undo the arrangement:

- The password is written to secure storage, backed by the Android Keystore.
  Only a non-secret marker — which account, which desktop, when — goes to
  preferences, which are a plain JSON file on disk.
- Reading it back prompts for biometrics or the device credential **every
  time**. There is no grace period, and unlocking the app does not count:
  opening the app proves someone opened it, while this prompt proves who is
  signing in to Windows right now.
- Saving is refused outright on a phone with nothing enrolled. The prompt is
  the only thing standing in front of the password, and a prompt nobody can
  answer is not a lock.
- A password saved for one account is never offered for another, or for
  another desktop. Sending it anyway would hand the password to a machine it
  does not belong to and burn a failed sign-in on the one it does.

The password can be removed from the phone at any time from the unlock panel.
A marker whose secret has gone — a cleared keystore, a reinstall — is dropped
at startup rather than offering a one-tap unlock that could only fail.

Anyone who does not turn this on keeps the previous behaviour exactly: the
password is typed per unlock and never stored.

## Protections

- The feature is disabled by default and must be installed with administrator
  approval.
- Pairing grants an explicit `unlock` scope only while the feature is enabled.
- A request is bound to one machine, one account, and one short-lived challenge.
- The desktop accepts at most three encrypted requests in ten minutes.
- The relay validates only the ciphertext envelope and cannot decrypt it.
- ProgramData files are restricted to SYSTEM, Administrators, and the installing
  user.
- The existing Windows sign-in providers remain enabled as a recovery path.
- A saved password is held in the Android Keystore and released only to a
  biometric or device-credential prompt, one prompt per unlock.

The mobile password is still represented briefly by managed Dart strings. The
app clears its password field and mutable plaintext buffers immediately after
encryption, but managed-runtime copies cannot be guaranteed to be overwritten.

## Installation And Removal

Build and install the Windows app, then use **Cài mở khóa Windows** in Remote
Control settings. The UAC-approved script installs the provider DLL, creates
the key, and registers the provider. Lock Windows once so LogonUI loads it.

`uninstall_remote_unlock.ps1` removes the provider registration, certificate,
and local data. The main Windows uninstaller calls it automatically.

## Verification

1. Enable remote unlock and pair the mobile app again so the pairing contains
   the `unlock` scope.
2. Lock Windows with `Win+L`; do not hibernate the machine.
3. Wait until the mobile app reports that the provider is ready.
4. Enter the Windows account password and submit the unlock request.
5. Confirm Windows unlocks and that `pending.bin` and `challenge.bin` are gone.
6. Repeat with a wrong password, an expired challenge, and a replayed request;
   all must fail while normal local sign-in remains available.

For a real deployment, protect the relay with TLS, authentication, short
pairing lifetimes, revocation, and production monitoring. Never send the
password itself as a relay command or store it in mobile preferences.
