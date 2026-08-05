# Curiositech Homebrew Tap

Homebrew formulae for tools by [Curiositech](https://curiositech.com).

## Installation

```bash
brew tap curiositech/tap
```

## Available Formulae

### Port Daddy

Port Daddy is the local control plane for coding-agent sessions, transcripts,
worktrees, permissions, and dynamic service ports. The daemon publishes its
actual endpoint; clients must discover it rather than assume a fixed port.

```bash
brew install curiositech/tap/port-daddy
brew services start port-daddy
```

Homebrew/launchd (or systemd on Linux) is the sole stable-daemon supervisor.
Normal health, restart, session, and dashboard work belongs in the Port Daddy
operator app; named development daemons stay isolated from the stable service.

### Port Daddy Console

```bash
brew install --cask curiositech/tap/port-daddy-console
```

## More Info

- [Port Daddy on GitHub](https://github.com/curiositech/port-daddy)
