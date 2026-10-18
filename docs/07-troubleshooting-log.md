# 7 · Troubleshooting log and lessons learned

Real problems hit while building SecureNet, taken from the technical log I kept during the project. Each one cost time; each one taught something.

## Network and virtualisation

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | At home nothing answered; `ping 8.8.8.8` → *Destination Host Unreachable* | Static config with `gateway4: 192.168.2.1`, the classroom router, which does not exist at home | Separate lab network and Internet access (host-only + NAT) |
| 2 | Services used `192.168.2.x` (classroom) for internal traffic | No distinction between internal and external network | Internal traffic only on the lab network, Internet only via NAT |
| 3 | Lost Internet after adding the host-only adapter | Default route still forced through the host-only side | Static IP **without gateway** on the lab NIC, DHCP on the NAT NIC |
| 4 | Working from home required a third VM | Workaround: Ubuntu router with two NICs | Replaced by VirtualBox host-only + NAT; one machine less |
| 5 | netplan changes lost after reboot | cloud-init rewrites `50-cloud-init.yaml` | `network: {config: disabled}` in `/etc/cloud/cloud.cfg.d/` |
| 6 | Pasting several commands into PuTTY skipped some | `sudo` password prompt swallowed the next pasted line | Run `sudo -v` first, paste one block at a time |

## WireGuard and remote administration

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 7 | Client could not reach the server | Endpoint set to the NAT IP `10.0.2.15`, unreachable from other VMs | Endpoint = the server IP on a network the client can reach |
| 8 | Endpoint pointed at a host-only IP the client was not on | Confusing "reachable" with "internal" networks | Client and server must share a routable network for the handshake |
| 9 | Client DNS did not resolve through Pi-hole | VPN down / client not on a network that reaches Pi-hole | Bring the tunnel up and set `DNS = 192.168.2.10` |
| 10 | No ping between the two Windows PCs, RDP failing | Network profile set to *Public* → firewall blocks ICMP/RDP | `Set-NetConnectionProfile -NetworkCategory Private` |
| 11 | RDP rejected credentials | Account only had a Windows Hello PIN, RDP needs a real password | Dedicated local user for RDP |

## Pi-hole v6 API

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 12 | `admin/api.php?summaryRaw` returned nothing | Legacy API removed in v6 | Use the REST API under `/api` |
| 13 | `401` with `Authorization: Bearer` | v6 does not accept bearer tokens there | Session auth: `POST /api/auth` |
| 14 | `401` with Basic Auth | Not supported by the REST API | Session auth |
| 15 | `password incorrect` | Used an *application password* instead of the web password | Web UI password |
| 16 | `no SID provided` in n8n | Session not passed between HTTP nodes | Send `X-FTL-SID` and `X-FTL-CSRF` headers from the AUTH node |
| 17 | `Referenced node doesn't exist` | Expression used `$node["AUTH"]` but the node had another name | Rename the node exactly `AUTH` |

## Fail2Ban

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 18 | Alerts sent but IPs no longer banned | `action = n8n` replaced the default ban action | `action = %(action_)s` + `n8n-webhook` |
| 19 | `jail.local` changes had no effect | File did not exist; edits went to the wrong place | Create `/etc/fail2ban/jail.local` |
| 20 | Ban happened but n8n never reacted | No action calling the webhook | Custom action with `curl` in `action.d/` |
| 21 | Banned IP could still use SSH | Most likely an already-open session: bans only block **new** connections | Restored the jail config; always test from a fresh connection |

## Docker and Compose

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 22 | `yaml: did not find expected key` | Wrong indentation and duplicated lines | Fix indentation; validate with `docker compose config` |
| 23 | `services.image must be a mapping` | Same block duplicated inside a service | Remove duplicates |
| 24 | `undefined volume securenet_n8n_data` | Volume not declared at the bottom of the file | Declare it under `volumes:` with `external: true` |
| 25 | Duplicated service / `container_name` conflicts | Copy-paste while iterating | One definition per service |
| 26 | Homepage crash-looping, `getaddrinfo EAI_AGAIN *` | `HOSTNAME=*` environment variable | Remove it |
| 27 | Homepage "Missing…" widgets | Widgets pointing to APIs that were not configured | Keep only widgets with working data sources |

## n8n

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 28 | n8n crash-loop, `EACCES: permission denied, open '/home/node/.n8n/config'` | Volume not owned by UID 1000 (`node`) | `chown -R 1000:1000` on the volume |
| 29 | All workflows "disappeared", owner setup screen again | Compose change mounted a different/new volume | Mount the original external volume |
| 30 | `Credential … does not exist for type telegramApi` | Encryption key changed, old credentials unreadable | Fixed `N8N_ENCRYPTION_KEY`; recreate the credential |
| 31 | `The requested webhook is not registered` (404) | Called `/webhook-test/` without listening in the editor | Use `/webhook/` and activate the workflow |
| 32 | Telegram messages with empty or `undefined` fields | Data arrived under `$json.body`, not `$json` | Normalise: `$json.body?.x ?? $json.x` |
| 33 | `=` printed before every value | `"={{ }}"` inside an expression → the `=` is literal | Remove the extra `=` *(still present in v1, fixed in v2)* |
| 34 | No "Execute Command" node available | Not available in that n8n setup | Restart containers through the Docker API instead |
| 35 | `wget: unrecognized option --method=POST` | n8n image uses BusyBox `wget` | `wget --post-data=''` |
| 36 | DNS error calling `docker-socket-proxy` | Proxy container not on the same Docker network yet | Add it to `securenet` |
| 37 | Restarting n8n from n8n cut the execution | A workflow cannot survive restarting its own engine | Never auto-restart n8n from itself |
| 38 | `Module 'fs' is disallowed` | Code node sandbox blocks Node modules | Read files with the native file nodes |
| 39 | `Access to the file is not allowed` | n8n only reads under `/home/node/.n8n-files` | Bind-mount `/opt/n8n-files` there |
| 40 | `scan_count = 0` | Extracted text was in `$json.data`, not `$json.Text` | Read the right field |
| 41 | `containers.filter is not a function` | Docker API response became one item per container | `$input.all().map(i => i.json)` |
| 42 | `this.getWorkflowStaticData is not a function` | Wrong API inside the Code node | `$getWorkflowStaticData('node')` |

## Uptime Kuma

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 43 | Body arrived as a string, fields empty | Content type / template sent JSON as text | Custom body + `Content-Type: application/json` header |
| 44 | `monitorJSON` / `heartbeatJSON` broke the JSON | Placeholders wrapped in quotes | Send them without quotes, or send only `msg` + a fixed `monitor_code` |
| 45 | 2–3 identical alerts per incident | Duplicated notifications + retries | Anti-duplicate TTL in the Code node; one notification per monitor |
| 46 | UP not detected | Only `[🟢 Up]` was matched, Kuma sent `[✅ Up]` | Match both |
| 47 | Events with `UNKNOWN` monitor | Notifications without `monitor_code` | Validate payload; flag instead of drop |

## Backups and AWS

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 48 | `awscli has no installation candidate` | Package dropped in Ubuntu 24.04 | Official AWS CLI v2 installer |
| 49 | `AccessDenied` on upload | Typo in the bucket name | Correct bucket |
| 50 | `Access denied for user 'root'` on dump | Wrong password hard-coded | Read `MYSQL_USER`/`MYSQL_PASSWORD` from the container |
| 51 | `Permission denied` (exit 126) from n8n SSH | Script not executable by the SSH user | Dedicated user, ownership + `chmod 750`, `docker` group |

## Lessons learned

1. **Design the network first.** Separating internal and Internet traffic removed a whole class of problems.
2. **Read the docs for the exact version.** Pi-hole v6 and n8n 2.x broke several tutorials written for older versions.
3. **Normalise every input.** Webhooks never arrive in the shape you expect; validate before using.
4. **Least privilege for automation.** Access to the Docker socket equals root on the host; expose only what is needed.
5. **Persistence is part of the design.** Volumes, permissions and encryption keys decide whether you lose everything on the next `compose up`.
6. **Test vs production matters**, even in n8n webhooks.
7. **Prove it works.** Several features "worked" in a demo but were incomplete. The post-delivery [security review](08-security-review.md) exists because of this lesson.
