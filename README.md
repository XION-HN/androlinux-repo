# haisa-des repository (gh-pages)

Auto-organized from GitHub Releases by organize-repo.yml workflow.
Last run: 2026-07-28T03:01:35Z (run #30324750330)

## Layout

- `apt-repo/` — Debian package repository
  - `dists/stable/Release` (+ InRelease / Release.gpg if signed)
  - `dists/stable/main/binary-aarch64/Packages` (+ .gz)
  - `pool/main/<首字母>/<包名>/<deb>`

- `pip-repo/` — PEP 503 Python simple index
  - `simple/index.html`
  - `simple/<首字母>/<规范化包名>/index.html` + wheel files

## Sources

- Release assets: https://github.com/XION-HN/haisa-des-repo/releases
- Build system: https://github.com/XION-HN/haisa-des-bootstrap
