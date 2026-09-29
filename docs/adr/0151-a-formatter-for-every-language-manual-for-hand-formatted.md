# ADR 0151: A formatter for every language; manual for hand-formatted ones

## Status
Accepted — implemented; VM-verified (`arch-combined`: every formatter via
conform, save vs `<leader>cf` behaviour, AUR vetting of nixfmt and
php-codesniffer). Extends ADR 0135's conform setup and ADR 0148's
VSCodium parity.

## Context
Several Registry languages had no formatter: shell, c/cpp, nix, php, scss,
xml, kdl, toml. `format_on_save` is on everywhere. Measured on the VM,
shfmt (`-i 2`) rewrites ~380 of the repo's 477 shell files (~16.5k diff
lines), mostly one-line functions and aligned `case` arms. kdlfmt rewrites
niri's `keybinds.kdl` (~400 lines) and taplo rewrites noctalia's
`config.toml` (~280 lines).

## Decision
- **Formatters (Registry rows, ADR 0141):**

  | Filetypes       | Formatter    | Source                                 |
  |-----------------|--------------|----------------------------------------|
  | sh, bash, zsh   | shfmt        | Host Core dev                          |
  | c, cpp          | clang-format | `clang`, already in Host Core          |
  | nix             | nixfmt       | Host Core AUR (official RFC 166 style) |
  | php             | phpcbf       | nvim `install.sh`, next to phpactor    |
  | scss, less      | prettier     | Host Core                              |
  | xml             | xmllint      | `libxml2`                              |
  | kdl             | kdlfmt       | Host Core dev                          |
  | toml            | taplo        | `taplo-cli`, Host Core dev             |

  php-codesniffer goes in `install.sh` because php hosts may run with
  `packages.inherit: false`. phpcbf uses the PSR-12 standard.
- **Manual-only formatting:** a row with `format_on_save = false` (shell,
  kdl, toml) formats on `<leader>cf` only, so the hand-formatted files stay
  as written. Every other language formats on save.
- **Response panes:** rest.nvim formats response panes with each filetype's
  `formatprg`: json → jq, html → prettier, xml → xmllint.
- **VSCodium parity (ADR 0148):**
  - c/cpp: clangd
  - nix: nix-ide + nixfmt
  - shell: bash-ide + shfmt
  - php: phpsab + phpcbf
  - toml: even-better-toml (Taplo)
  - scss/less: prettier
  - xml, kdl: custom-local-formatters running xmllint/kdlfmt, with v1hz.kdl
    registering the kdl language

  `[shellscript]`/`[kdl]`/`[toml]` set `formatOnSave: false`.
- **php-codesniffer is allowlisted** for `skip-checksum` (ADR 0149): its
  only `SKIP`s are the `.asc` signatures, which `validpgpkeys` verifies.

## Considered Options
- **Bulk reformat + format on save everywhere:** rejected. It's a 16k-line
  churn commit and drops the aligned style.
- **Format on save without a bulk pass:** rejected. Churn would land in
  whatever file is touched next.
- **php-cs-fixer:** rejected. The AUR package is flagged out-of-date.
- **Loosening aur-vet's skip-checksum for signature files:** deferred in
  favour of a per-package allowlist entry.

## Consequences
- nixfmt builds from the AUR against Haskell libraries (ghc makedepend),
  which makes it a slow first install.
- latex/typst stay parser-only (no files in use); http has no formatter.
- The same aligned-style trade-off applies if another hand-formatted
  language is added: mark its row `format_on_save = false`.
