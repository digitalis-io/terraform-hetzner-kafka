# ADR-0008: Kafka TLS certificates from a project CA (`custom` mode), SASL/SCRAM for client identity

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #14
- **Amends:** ADR-0004 (Kafka listeners are no longer PLAINTEXT once security is enabled)

## Context
The MVP runs Kafka with PLAINTEXT listeners on the Hetzner private network (ADR-0004). Hetzner firewalls do not filter private traffic, so anything in the network can read and write every topic. The `axonops.axonops.kafka` role (0.6.x) supports TLS, SASL (SCRAM-SHA-512 or PLAIN) and the KRaft StandardAuthorizer. For TLS it needs PEM material from one of three sources:

- `custom`: PEM files on the control node, copied to each host.
- `pki_agent`: PEM files written on each host by `axonops.axonops.pki_agent`.
- `generate`: a self-signed CA the role creates in `/tmp` on the control node. The CA is lost when `/tmp` is cleaned, so new hosts can no longer be signed by the same CA. The role marks it dev only.

## Decision
- The example enables TLS, SASL/SCRAM-SHA-512 and ACLs (`SASL_SSL` on 9092 and 9093).
- TLS uses `kafka_tls_mode: custom`. `make certs` runs `ansible/certs.yml`, which uses `community.crypto` (already a dependency) to create a project CA and one certificate per inventory host. The SANs are the private IP (`kafka_node_ip`) and the inventory hostname. Output goes to `ansible/tls/`, which is gitignored. The playbook is idempotent: re-running it after a scale-out signs only the new hosts.
- `kafka_tls_client_auth: none`. SASL/SCRAM authenticates clients and TLS encrypts traffic. Clients do not need their own certificates.
- Secrets (inter-broker password, application users) live in `ansible/group_vars/kafka/vault.yml`, encrypted with Ansible Vault. `site.yml` checks for the secrets before it changes any host.
- `generate` stays available for disposable test clusters (molecule). `pki_agent` remains an option for teams that already run the AxonOps PKI agent.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| `custom` + `make certs` project CA | Durable CA; scale-out signs new hosts; no extra service | CA private key on the operator's machine must be protected |
| `generate` | No setup | CA in `/tmp`; lost CA breaks scale-out; role marks it dev only |
| `pki_agent` | Automatic rotation | Needs a PKI backend (for example Vault PKI) that this project does not provision |
| mTLS (`kafka_tls_client_auth: required`) | Strong client identity without passwords | Every client needs a certificate signed by the project CA; duplicates SASL |

## Consequences
- Security works only on a **fresh** cluster: SCRAM credentials for the inter-broker user are written when storage is formatted. Switching a running PLAINTEXT cluster to SASL_SSL is a manual migration and is out of scope.
- `ansible/tls/ca.key` can sign certificates that every broker trusts. Store it offline or encrypt it with Ansible Vault after use.
- Host certificates are valid for 825 days and the CA for 10 years. To rotate a host certificate, delete it from `ansible/tls/`, then run `make certs configure`.
- `ssl.endpoint.identification.algorithm` is empty in the role's broker and client configuration, so hostname verification is off. Anyone holding any host key signed by the project CA can impersonate any broker. This is acceptable only because Kafka is reachable on the private network alone (ADR-0004); protect host keys and `ca.key` accordingly. The SANs are set correctly, so verification can be enabled later.
- `ca.key` is needed again to sign new hosts after a scale-out. If it is stored offline, restore it before `make certs`.
- No automatic renewal or expiry alerting. Check expiry with `openssl x509 -checkend <seconds> -in ansible/tls/<host>.crt`.
