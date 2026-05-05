# Security Policy

This repository is a sanitised public version of a cybersecurity lab.

## Sensitive Data Policy

Do not commit:

- Passwords or password lists.
- Private keys.
- WireGuard client/server keys.
- Telegram bot tokens.
- AWS access keys, secret keys or session tokens.
- `.env` files with real values.
- Exported virtual machines containing credentials.
- Screenshots that expose private IPs, tokens, users or dashboards with secrets.

Use placeholders such as:

```text
CHANGE_ME
REDACTED
YOUR_TOKEN_HERE
YOUR_BUCKET_NAME
```

## Responsible Use

Attack simulations documented in this project must only be executed in controlled lab environments owned by the author or explicitly authorised for testing.
