# Local LLM inference — foundations

How local models are run and tuned on this fleet, with geekom (the only
GPU-capable host) as the reference machine. This is the durable record of the
*measured* facts and the decisions they justify — the 35b MoE reference model
and the 27b it was measured against — plus the protocol for the next local
model, so tuning starts from measurement instead of folklore.

Config lives in [hosts/geekom/default.nix](../hosts/geekom/default.nix)
(daemon env) and [modules/home/opencode.nix](../modules/home/opencode.nix)
(client-side model metadata). The version-pinning decision (unstable) is
in [doc/workflow.md](workflow.md), "Need a newer version before the next
release?".

## The machine

| fact | value | how to re-check |
| --- | --- | --- |
| RAM | 64 GB DDR5-5600 (2×32 GB), 54.5 GiB usable | `free -h`; `nix shell nixpkgs#inxi -c inxi -m` |
| iGPU | Radeon 890M (gfx1150, RDNA 3.5, STRIX1) | `journalctl -u ollama \| grep "inference compute"` |
| VRAM carve-out | 8 GiB (BIOS fixed) | `cat /sys/class/drm/card0/device/mem_info_vram_total` |
| GTT | 27.3 GiB (amdgpu default = ½ of usable RAM) | `cat /sys/class/drm/card0/device/mem_info_gtt_total` |
| Runner pool | **35.3 GiB** (Vulkan reaches VRAM + GTT) | same journal line, `total=` |

Two things to read off the machine rather than from a spec sheet:

- RAM is 64 GB (2×32 GB) — ask `inxi -m`/`dmidecode`, never the model name.
- **The runner pool moves when RAM moves.** GTT defaults to half of usable RAM
  (amdgpu default), which is where 27.3 GiB of the 35.3 GiB pool comes from;
  halving RAM halves GTT but not the 8 GiB carve-out. No `amdgpu.gttsize=`
  kernel param is set — the default is sufficient, and carving more would only
  steal from the shared pool the runner reaches anyway.

## The current model — and why its architecture changes the math

`qwen3.6:35b-a3b-coding-mtp-q4_K_M` (35.5B MoE, 8 active experts, Q4_K_M,
20.2 GiB weights). Read from `/api/show` (the daemon, not the model card, is
what enforces limits):

| field | value | meaning |
| --- | --- | --- |
| `qwen35moe.full_attention_interval` | 4 | **hybrid attention** (Qwen3-Next style): only 10 of the 41 layers do full attention (every 4th); the rest are linear/recurrent |
| `attention.head_count_kv` | 2 | tiny KV footprint per token (GQA) |
| `key_length`/`value_length` | 256 | head dim |
| `nextn_predict_layers` | 1 | MTP head (multi-token prediction) |
| `context_length` | 262144 | native window, no YaRN trim |

**KV cache ≈ 22 KB/token** for this model:

```
bytes/token = 2 (K+V) × full-attn-layers × kv_heads × head_dim × bytes/elem
            = 2 × 10 × 2 × 256 × 2 (f16) = 20 KB
```

At 262144 tokens that is 5.0 GiB — the runner logs it as `llama_kv_cache:
Vulkan0 KV buffer size = 5120.00 MiB`, and the MTP head carries its own
single-layer cache (`… 262144 cells, 1 layers …`) for a second 512 MiB: 5.5 GiB
total. A dense-attention 35B would need ~64 GiB and could not do this; the
recurrent layers add a fixed 188 MiB (`RS buffer`) regardless of context.

Measured decode is **flat from 22k to 262k context depth** (29-31 tok/s):
the linear-attention layers make long context nearly free. Do not size
context on dense-model intuition.

## Measured baselines (Vulkan, 100% GPU, MTP on)

| metric | value | condition |
| --- | --- | --- |
| cold load | 11-14 s | page cache cold; 20.2 GiB from NVMe (runner itself spawns in ~4 s) |
| reload | ~11 s | page cache warm |
| decode | 29-31 tok/s | flat across context depths; MTP on |
| prefill (fresh, 1520-token prompt) | ~364 tok/s | long-prompt TTFT is prefill-bound |
| MTP A/B (draft_num_predict) | 2 → **31-32 t/s**; off → 24; 4 → 22 | the GGUF ships 2 and the daemon already passes `--spec-draft-n-max 2`; **2 is optimal — do not touch** |
| full 262144 load | fits | 20.2 weights + 5.5 KV + ≤0.3 compute; ~9 GiB GTT headroom; 29 tok/s after |
| TTFT (warm, short prompt) | ~120 ms | prompt-eval span, prompt metadata already cached |
| GPU placement | 100% GPU, `size_vram` = full model size | `ollama ps` is the check |
| iGPU on vs off (FIM A/B, qwen2.5-coder, same prompt) | 3B: 20 → 22 tok/s; 1.5B: 37 → 41 | ~10%: the iGPU shares the CPU's DDR5, so decode is bandwidth-bound — the real gain is that inference stops competing with the editor for cores |
| 27b shallow decode | 8 t/s (35b: 33) | `qwen3.8:…-ctx128k` 100% GPU, seed 42, temp 0, 300 tok — 2026-09-17 A/B |
| 27b decode at depth | 10 t/s after 11926-tok prefill (35b: 32) | same protocol; both models flat with depth — hybrid attention holds |
| 27b prefill | 97 t/s @ 3421 tok / 91 @ 11926 (35b: 364/348) | fresh prompts each time — a repeated prompt hits the KV cache and lies |
| 27b full-window load | 45/66 layers, 5 GiB KV on CPU | at 262144: 16 GiB KV (64 KB/token) does not fit; decode 4.65 t/s, prefill 14.5 t/s |
| 27b 128k load | 66/66 layers, 8.5 GiB KV all GPU | the `-ctx128k` tag at 131072: same weights, halves the KV — the only sane runtime for this model |

Benchmark one-liners (paste-ready, machine is left clean afterwards — model
unloaded, keep_alive restored):

```sh
# decode speed (warm; run after one warm-up request)
curl -s http://127.0.0.1:11434/api/generate -d '{"model":"MODEL","prompt":"PROMPT","stream":false,"keep_alive":"5m","options":{"num_predict":300,"seed":42,"temperature":0}}' \
  | jq -r '(.eval_count/.eval_duration*1e9|round|tostring)+" tok/s"'

# prefill speed (fresh prompt each time — a repeated prompt hits the KV cache and lies)
curl -s http://127.0.0.1:11434/api/generate -d "$(jq -n --arg p "$LONG_PROMPT" '{model:"MODEL",prompt:$p,stream:false,keep_alive:"5m",options:{num_predict:5}}')" \
  | jq -r '((.prompt_eval_count/.prompt_eval_duration*1e9)|round|tostring)+" tok/s prefill"'

# per-request context override (works regardless of daemon default)
# ... add "options":{"num_ctx":131072} to any request

# memory placement + context in effect
curl -s http://127.0.0.1:11434/api/ps | jq '.models[] | {size, size_vram, context_length}'

# what the runner actually does (flags, buffers, tiers)
journalctl -u ollama --no-pager | grep -E 'llama_server|llama_kv_cache|vram-based'
```

## Daemon decisions (the "why" next to each knob)

Every knob here has a measurement behind it; these verdicts are the record:

| setting | value | why (measured) |
| --- | --- | --- |
| `OLLAMA_CONTEXT_LENGTH` | `262144` | left unset, the vram-tier default for this pool is 32768 (`vram-based default context … default_num_ctx=32768`, the ≥23 GiB bracket); hybrid attention makes 256k fit with ~9 GiB headroom; decode flat |
| `OLLAMA_KEEP_ALIVE` | `1h` | kills the 11-14 s reload in interactive use; model frees itself after an hour; `-1` rejected (22 GiB would never free on a gaming box) |
| `OLLAMA_IGPU_ENABLE` | `1` | without it the iGPU is discovered then dropped (`dropping integrated GPU; to enable, set OLLAMA_IGPU_ENABLE=1` in the journal) and every request is served from CPU. `ollama ps` → 100% GPU is the check |
| `OLLAMA_FLASH_ATTENTION` | unset (auto) | already active (`--flash-attn auto` in the runner cmd); pinning `=1` adds nothing |
| `OLLAMA_KV_CACHE_TYPE` | unset (f16) | q8_0 would halve the KV (5.5 → 2.7 GiB at 262144, a fifth of the resident footprint) and the full window already fits with headroom; it costs quality and is global to all models. Revisit only for a dense-attention model, or a load that stops fitting |
| `OLLAMA_NUM_PARALLEL` | unset (1) | slots multiply KV and split memory bandwidth; single-user opencode gains nothing at 2 |
| `OLLAMA_MAX_LOADED_MODELS` | unset (auto) | auto-compute already allows what fits |
| MTP `draft_num_predict` | 2 (GGUF-shipped) | measured A/B above; **do not touch** |
| `loadModels` / boot preload | not used | pulls but does not preload; boot-time preload would pin 22 GiB and slow every boot for nothing |
| `OLLAMA_GPU_OVERHEAD` | 0 (default) | makes the scheduler assume less VRAM (conservative packing) — relevant only if ollama must refuse loads while a game hogs GTT; not needed today |
| runner flags (`-b/-ub 512`, `--context-shift`, `--keep 4`) | daemon-fixed | not user-tunable via env; no measured pathology |

Package: `unstablePkgs.ollama-vulkan`. Vulkan-not-ROCm is the standing choice:
ROCm on this part is the reported 6.42 tok/s (ollama#9999 — an
`HSA_OVERRIDE_GFX_VERSION=11.5.1` workaround on the same Ryzen AI 9 HX 370,
2.5× *slower* than CPU-only there), against the measured 29-31 tok/s Vulkan
path; Vulkan's GTT spill is also exactly what makes 256k context possible here.

BIOS carve-out (8→16 GiB) and `amdgpu.gttsize=` were considered and rejected:
decode is flat with KV resident in GTT, and carving VRAM only steals from the
shared pool the runner reaches anyway.

No service-level config is needed for GPU access: the `services.ollama` module
already ships `SupplementaryGroups=render`, `DeviceAllow=char-drm` and
`PrivateDevices=false`, so its `DynamicUser` reaches `/dev/dri/renderD128` as-is.

(The 27b at full 262144 is the load that does not fit — 16 GiB KV against a
35.1 GiB available pool. For a future model that makes that worth revisiting,
the lever order is: smaller per-request `num_ctx`, then
`OLLAMA_KV_CACHE_TYPE=q8_0` (halves KV; global to all models), and only then
the BIOS carve 8→16, whose net pool gain is only +4 GiB because GTT is half of
what the carve-out leaves. Still measure first.)

## Derived local tags — imperative, documented, not automated

Tags live in `/var/lib/ollama/models/manifests/…` as local manifests naming
content-addressed blobs; the registry is consulted only at `ollama pull`
time, never at load. A tag the registry does not have must therefore be
created locally with `ollama create` and cannot be reproduced by the flake.
The daemon-side half is the same Tier-2 imperative store as `ollama signin` —
see [doc/secrets.md](secrets.md). The client-side half (the opencode model entry)
IS declarative, in modules/home/opencode.nix; the tag is not. The failure mode is
loud, not silent: a missing tag errors on first use, and the recovery is the
recipe below.

One derived tag exists today:

- `qwen3.8:27b-mtp-q4_K_M-ctx128k` — the plain tag's weight and projector
  blobs, plus one params blob. The baked `num_ctx 131072` wins over the
  daemon's `OLLAMA_CONTEXT_LENGTH=262144` at load time, while the 35b (no
  baked parameter) keeps 262144 — per-model context without any daemon config.
  Why not the plain tag: at the GGUF's native 262144 its KV is 16 GiB
  (64 KB/token — 16 full-attn layers × 4 KV heads, against the 35b's 10 × 2 =
  20 KB/token) and the runner could only place 45/66 layers, dropping decode to
  4.65 t/s; at 131072 it runs 66/66.

Recreate after a reinstall (plain-tag pull first):

```sh
printf 'FROM qwen3.8:27b-mtp-q4_K_M\nPARAMETER num_ctx 131072\n' > /tmp/m
ollama create qwen3.8:27b-mtp-q4_K_M-ctx128k -f /tmp/m
```

Revisit trigger: a second derived tag, or a reinstall actually biting,
promotes this to an idempotent systemd oneshot. Until then the recipe above
is the whole automation — partial automation of an already-manual pull is
not worth a unit file.

## opencode ↔ daemon context agreement

`modules/home/opencode.nix` declares `limit.context = 262144` for this model
(from `/api/show`, matching the GGUF). Left alone, the daemon's vram-tier
default (32768 for this pool) silently overrides it per request — opencode
sends no `num_ctx`, so the client's declared limit and the daemon's enforced
one disagree by 8×. The daemon env sets 262144 and the two agree. When adding a
local model:

1. read `context_length` from `/api/show` (the daemon trims to what it loads),
2. set the client `limit.context` to that figure,
3. if the daemon default differs, either set `OLLAMA_CONTEXT_LENGTH` for the
   model class or send `num_ctx` per request — never leave the two disagreeing.

## Future-model protocol (measure before adopt)

Before adopting any new local model on geekom:

1. **Pull and inspect**: `ollama show MODEL` — note family, `full_attention_interval`
   (hybrid vs dense), `head_count_kv`, `nextn_predict_layers` (MTP),
   `context_length`.
2. **Estimate memory**: weights (file size) + KV (formula above — for dense
   models: `2 × layers × kv_heads × head_dim × ctx × 2 bytes`) + ~0.3 GiB
   compute. Must fit in 35.3 GiB pool (or expected pool after any RAM change).
3. **Load at target context**: `num_ctx` per request; check `ollama ps` for
   100% GPU and `journalctl` for buffer sizes and no CPU fallback.
4. **Benchmark**: decode (warm, fixed seed), prefill (fresh long prompt),
   load time (unload → reload). Compare against the baseline table above.
5. **MTP check**: if the GGUF ships `draft_num_predict`, A/B it (0 vs shipped
   value vs 2×) with the decode one-liner before trusting the default.
6. **Only then** touch env vars in `hosts/geekom/default.nix` (geekom-only
   blast radius) and the model entry in `modules/home/opencode.nix` — then run
   `./scripts/check-hosts.sh` and account for every `drvPath` delta it prints
   ([doc/workflow.md](workflow.md)).
7. **Record** the measured row in the table above and date it.