# SSH Agent and Zellij

## Raspberry Pi Configuration

Use gpg-agent SSH support, configured by `rpi/setup_gpg_agent.sh`, on Bookworm
and Trixie. Do not replace it with an OpenSSH agent as part of the OS migration.
`enable-ssh-support` and the SSH cache TTLs are stored in
`~/.gnupg/gpg-agent.conf`; `loginctl enable-linger` keeps the user manager alive
after the last SSH session ends. The fixed socket is obtained with
`gpgconf --list-dirs agent-ssh-socket`.

In an SSH session, `shell/zshrc` points `~/.ssh/auth_sock` to a live forwarded
agent first. If it is unavailable, the configuration falls back to the local
gpg-agent socket. Reevaluate this in a new interactive shell after disconnect;
an already-running process does not automatically rerun shell initialization.
Do not set GitHub `IdentityAgent` to the Pi's socket, as it would bypass the
forwarded-agent preference. Local Mac sessions are outside the SSH guard.

## Initial Key Loading and Reboot

Generate a passphrase-protected Pi-specific key and register its public part
with the intended GitHub account. Load the key into gpg-agent once with
`SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)" ssh-add ~/.ssh/<key>`.
This requires interactive passphrase input. Update `GPG_TTY` and run
`gpg-connect-agent updatestartuptty /bye` from the interactive terminal if
pinentry cannot find it. Do not copy private keys into the public repository.

The long cache TTL does not survive reboot. Reconnect and reload/unlock the
key after reboot. Preserve the private gpg-agent key store securely if the
host is rebuilt, or generate/register a replacement key.

## Verification

Check `loginctl show-user "$USER" -p Linger`,
`systemctl --user is-active gpg-agent-ssh.socket`, and `ssh-add -l` using the
fixed socket. Verify GitHub authentication without forwarding and use
`git ls-remote` on an authorized repository to check read access without
creating a test commit. Actual push permission requires an intended push;
do not create remote commits solely to test the agent.

Detach Zellij, disconnect SSH, reconnect with forwarding disabled and check
the socket and Git operation in a new shell inside the preserved session.
Repeat after reboot with the documented key-unlock step. Auth success alone
does not prove that an existing detached pane switched from a dead socket.

## Rollback

Save the original gpg-agent configuration and linger setting before applying
the setup. To undo, restore those settings and the previous socket/link setup.
Only disable linger if it was previously disabled and no other user services
depend on it. Restarting gpg-agent clears cached passphrases and requires
interactive unlocking again. Do not remove private keys to undo configuration.
