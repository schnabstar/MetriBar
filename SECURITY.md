# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Send an email to **info@schnabel.it** instead.

Please include the MetriBar version, your macOS version, steps to reproduce and the impact you see. Leave out real passwords and host names.

You can expect an acknowledgement within a week. MetriBar is maintained by one person in their spare time, so please allow reasonable time for a fix before disclosing details publicly.

## Supported versions

MetriBar is in preview. Security fixes go into the latest release only.

## Scope

In scope: the MetriBar app and the MetriBarKit package in this repository, for example credential handling, certificate validation and pinning, handling of server responses and the content of diagnostic reports.

Out of scope: vulnerabilities in Glances itself. Report those to the Glances project according to [its security policy](https://github.com/nicolargo/glances/security/policy).

## How MetriBar protects you

MetriBar only reads from the servers you add, stores passwords in the Keychain, validates TLS certificates (or exactly the certificate you pinned), warns before sending a password over plain HTTP and collects no data. The details, and what the operator of a Glances server is responsible for, are in [Docs/security.md](Docs/security.md).
