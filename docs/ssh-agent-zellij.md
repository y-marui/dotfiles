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
pinentry cannot find it. The setup script selects `pinentry-curses` so the
passphrase prompt works without a display; the default `pinentry-gnome3` makes
`ssh-add` hang on a headless host. After `ssh-add`, gpg-agent asks once more for
a passphrase to protect the key in its own storage. Do not copy private keys into the public repository.

The long cache TTL does not survive reboot. Reconnect and reload/unlock the
key after reboot. Preserve the private gpg-agent key store securely if the
host is rebuilt, or generate/register a replacement key.

### Unlocking After Reboot

After a reboot `ssh-add -l` still lists the key, but the passphrase cache is
empty and non-interactive use fails with `agent refused operation`. Unlock it
from a real terminal, preferably a plain SSH session outside Zellij
(`NO_ZELLIJ=1 ssh -t <host>`):

~~~sh
export GPG_TTY=$(tty)
gpg-connect-agent updatestartuptty /bye
SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)" ssh -T git@github.com
~~~

- Always name the fixed socket. Otherwise `ssh -T` uses the forwarded agent of
  the Mac and succeeds without touching the Pi's gpg-agent, which hides the
  locked state.
- `pinentry-curses` needs a real TTY and a large enough window. Without a TTY
  or with a tiny pane it fails with `Screen or window too small`, which the
  client reports only as `agent refused operation`.
- To find the cause, add `log-file <path>` and `verbose` to `gpg-agent.conf`,
  run `gpgconf --reload gpg-agent`, retry, then remove the lines again.

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
