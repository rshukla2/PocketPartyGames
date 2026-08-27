# Security policy

Version 1.x receives security fixes. Do not open a public issue for a vulnerability involving join authentication, TLS pinning, private-state leakage, command authorization, or denial of service. Use GitHub’s private vulnerability reporting when enabled, or contact the repository owner privately through GitHub.

Include affected version/platform, reproduction steps, impact, and any safe proof of concept. Do not test against rooms or devices you do not own or have permission to use. We aim to acknowledge reports within seven days.

Room certificates are intentionally self-signed and pinned from a QR/manual fingerprint; trust never falls back to the public CA store. A matching fingerprint is mandatory. Nearby remains confined to the local network and should not be port-forwarded.
