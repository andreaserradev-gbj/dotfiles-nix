# Secret management (sops-nix)

Secrets that **configuration itself consumes** (the context7 MCP API key was
the first) live in this repo as age-encrypted ciphertext, committed and
pushed like any other file. Decryption happens on each machine, at
activation, with that machine's own SSH host key — by
[sops-nix](https://github.com/Mic92/sops-nix). Nothing is base64-obfuscated
or stored in a script; the ciphertext in the store is inert, and CI builds
systems from it without holding any key.

What this file covers: the storage model, the edit workflow, the trust
boundary, which credentials live where (the tier table), and what this
scheme does — and does not — protect against.

## Storage model

`secrets/andrea/secrets.yaml` holds the secrets, encrypted with
[AES256-GCM](https://en.wikipedia.org/wiki/Galois/Counter_Mode). Committed
ciphertext looks like this (an abridged excerpt of the real repo file —
metadata elided, and within the `sops:` block only the shape is shown):

```yaml
CONTEXT7_API_KEY: ENC[AES256_GCM,data:GH6XZ2/…,iv:…,tag:…,type:str]
sops:
    age:
        - recipient: age10p2fkelpq…
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            …
```

- **One random data key per file**, generated at each save. All values in
  the file are encrypted with it — adding a secret never re-encrypts more
  than one blob per value.
- **Per-recipient wrapping.** The data key is itself encrypted once per
  recipient (one `enc:` block each). Any single recipient's private key can
  unwrap the data key and read everything in the file — there is no
  per-key split (see the shamir trap in [.sops.yaml](../.sops.yaml)).
- **Integrity.** sops computes a MAC over the plaintext structure: an
  attacker with repo write access can replace the whole file, but cannot
  *tamper* — flip a character, swap a value — without the MAC failing the
  decryption on every machine.
- **`.sops.yaml` is not secret.** It lists public keys only and says who
  may decrypt what; it is the policy file. It is safe (and required) in a
  public repo.

### The path a secret takes

```
secrets/andrea/secrets.yaml   (committed ciphertext; inert in the nix store)
        │  sops-nix activation, host SSH key unwraps the data key
        ▼
/run/secrets/CONTEXT7_API_KEY  (ramfs, mode 0400, owner andrea, gone at reboot)
        │  zsh initContent: export CONTEXT7_API_KEY="$(cat … 2>/dev/null)"
        ▼
opencode.json mcp.context7 → "Authorization: Bearer {env:CONTEXT7_API_KEY}"
```

The shell export is **guarded** (`2>/dev/null`): on a host where no secret
is provisioned — before the first rebuild, or a non-recipient machine — the
variable is simply empty and opencode degrades to context7's anonymous
(rated-limited) mode. No shell ever errors over a missing secret.

## Trust boundary

| host        | can decrypt `secrets/andrea/` | declares/mounts secrets | why                                        |
| ----------- | ----------------------------- | ----------------------- | ------------------------------------------ |
| geekom      | yes (own host key)            | yes (dev gate on)       | Andrea's machine                            |
| nixos (VM)  | yes (own host key)            | yes (dev gate on)       | Andrea's machine; see the reinstall note    |
| **hplaptop**| **no** — host key is not a recipient | **no** — dev gate off | Elisa's machine; non-technical user       |

The boundary is enforced at **two independent layers**:

1. **Encryption layer** — `.sops.yaml` decides who can decrypt. hplaptop's
   host key is not a recipient, so even the ciphertext copied there is
   opaque bytes.
2. **Declaration layer** — the `sops.secrets` block lives inside the
   `local.dev.enable` gate in `modules/nixos/dev.nix`. hplaptop (gate off)
   never evaluates it: nothing is added to its activation script,
   `/run/secrets` stays empty, no sops binary is pulled into the closure.
   Belt to the braces: a secret nobody declares is never shipped at all.

A future namespace for another person (e.g. `secrets/elisa/`) would get its
own `path_regex` + `key_groups` entry and use exactly this same two-layer
pattern. It is deliberately not created until a real need exists.

> **VM reinstalls rotate the host key.** A wiped or recreated VM generates a
> new SSH host key and is silently locked out of `secrets/andrea/` — the
> data key wrapped for the old key can't be opened. Fix is one command on a
> machine with the personal key, then rebuild:
>
> ```sh
> ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub   # on the VM: get new host pubkey
> # → paste the new age1… under keys: &nixos in .sops.yaml
> sops updatekeys secrets/andrea/secrets.yaml      # re-wrap the data key to all recipients
> git add .sops.yaml secrets/andrea/secrets.yaml && git commit
> ```
>
> This is the accepted tradeoff for including the VM as a recipient at all:
> without it, the VM could only decrypt when geekom was reachable.

## Workflow: adding, editing, rotating

Editing runs from any machine with the personal age key
(`~/.config/sops/age/keys.txt`, the sops default location) inside this
repo's devShell — `sops`, `ssh-to-age` and `age` are already in it, so no
ad-hoc `nix shell` is needed:

```sh
nixcfg                # cd ~/dotfiles-nix; direnv loads the devShell
sops secrets/andrea/secrets.yaml   # opens $EDITOR on the DECRYPTED file
```

Rules that have bitten once already:

- **Verify after every save.** `head -1 secrets/andrea/secrets.yaml` must
  start with `CONTEXT7_API_KEY: ENC[`. A save that fails (or an editor
  writing a scratch placeholder) leaves plaintext on disk — delete and
  retry. sops writes ciphertext only after the editor exits; the
  `/tmp/sopsNNN` file it shows is scratch, never the target.
- **`git add` the ciphertext before any `--flake` command.** sops-nix
  validates at *evaluation* time that every declared key exists in the
  ciphertext — an untracked file fails the build with a misleading
  "path does not exist" (see [doc/workflow.md](workflow.md)).
- **Adding a new secret key** is the same `sops` edit, plus one
  `sops.secrets.<NAME>` entry in `modules/nixos/dev.nix` (and an export or
  consumer wherever it is read). The eval-time check catches a spelling
  mismatch between the two.
- **Rotating a credential**: edit the value via `sops`, commit — a new data
  key is generated on every save, so rewrapping to all recipients happens
  automatically. Recipient *changes* (a new or rotated host key) additionally
  need `sops updatekeys`, per the note above.
- **`key_groups` without shamir** — inside a `key_groups` entry, a `-`
  before `age:` starts a *second* group, which enables shamir splitting and
  locks every single machine out (each group would hold only a share of the
  data key). The trap is annotated in place in [.sops.yaml](../.sops.yaml).

## Credential tiers

Not everything goes through sops — the policy is "declarative ciphertext for
configuration-consumed secrets only":

| tier | what | where it lives | why not sops |
| ---- | ---- | -------------- | ------------ |
| 1 — config-consumed | `CONTEXT7_API_KEY` (MCP header) | `secrets/andrea/secrets.yaml` | read by config at runtime; needs a machine-provisioned value |
| 2 — keyring logins | `gh`, `ollama`, opencode's `auth.json` | OS keyring / OAuth flows, imperative | interactive, per-user, needs browser round-trips; `gh auth login` etc. survive in a keyring that flake commits cannot and should not touch |
| 3 — browser-internal | site logins, cookies, saved passwords | inside each browser's own store | never exported, on any tier; treating browser state as config would be a security regression |

Practical consequence of being Tier 2: after a **host reinstall**, the
interactive logins must be re-run once:

- `gh auth login` (git and CLI credential helper)
- `ollama signin` (account sync)
- opencode: re-run its auth flow (`auth.json` is regenerated)

Only Tier 1 comes back for free — reboot after rebuild and `/run/secrets`
is filled from the committed ciphertext.

## Threat model — what this protects against

- **Reads of the public repo / store snooping.** Covered: the repo holds
  only ciphertext; the store holds the same inert ciphertext; plaintext
  exists only in `/run/secrets` (ramfs, 0400) and in the consuming process.
- **HNDL (harvest-now, decrypt-later).** Accepted for these keys. The
  secrets here are low-value rate-limit keys, not payment credentials; if
  that changes, the tier table is the thing to revisit first.
- **Repo-write attacker.** Can replace the ciphertext with their own, but
  tampering with existing ciphertext fails the MAC — and the recipient list
  in `.sops.yaml` diffs is the tripwire: a new recipient key appears in git
  history.
- **Compromised host.** A rooted recipient machine can read its own
  secrets — no scheme fixes that, short of not shipping the secret there at
  all. Hence hplaptop's two-layer exclusion: the cheapest way to keep a
  secret off a machine is to never put it in its evaluation.

---

- Recipient policy and the shamir trap, annotated in place: [.sops.yaml](../.sops.yaml)
- The declaration gate (two-layer boundary, code side): [modules/nixos/dev.nix](../modules/nixos/dev.nix)
- Rebuild commands used after edits (`nrs`, `nrb`): [doc/workflow.md](workflow.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)
