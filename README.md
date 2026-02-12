# Curiositech Homebrew Tap

Homebrew formulae for tools by [Curiositech](https://curiositech.com).

## Installation

```bash
brew tap erichowens/tap
```

## Available Formulae

### Port Daddy

Authoritative port assignment service for multi-agent development environments. No more port conflicts between parallel Claude sessions.

```bash
brew install erichowens/tap/port-daddy

# Start the daemon
port-daddy install

# Get a port for your project
PORT=$(get-port my-project)
npm run dev -- --port $PORT
```

## More Info

- [Port Daddy on GitHub](https://github.com/erichowens/port-daddy)
