# Architecture

SecureNet separates the physical network from the internal lab network. This makes the project portable between classroom, home and other environments.

## Network Model

| Network | Purpose | Notes |
| --- | --- | --- |
| External network | Internet access | DHCP/NAT/bridge depending on environment |
| Host-Only network | Stable internal lab communication | `192.168.56.0/24` |
| VPN network | Secure remote access | WireGuard tunnel |

## Machines

### PC1 - Security Gateway

Responsibilities:

- Pi-hole DNS server.
- WireGuard VPN endpoint.
- Fail2Ban protection.
- Security-focused gateway services.

Internal lab IP:

```text
192.168.56.10
```

### PC2 - Automation Hub

Responsibilities:

- Docker service host.
- n8n automation workflows.
- Uptime Kuma monitoring.
- Portainer management.
- Dashboard and backup orchestration.

Internal lab IP:

```text
192.168.56.20
```

## Design Decisions

- Use DHCP for external connectivity to avoid depending on a fixed classroom gateway.
- Use Host-Only networking as the stable project backbone.
- Use VPN as the only remote entry point into the internal lab.
- Keep monitoring and automation separated from gateway/security services.
