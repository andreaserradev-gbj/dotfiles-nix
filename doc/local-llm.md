# Local LLM inference — foundations

How local models are run and tuned on this fleet, with geekom (the only
GPU-capable host) as the reference machine. This is the durable record of
*measured* facts and decisions from the 2026-09-11 optimization study of
`qwen3.6:35b-a3b-coding-mtp-q4_K_M` — and the protocol for the next local
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
| VRAM carve-out | 8 GiB (BIOS fixed) | `cat /sys/class/drm/card1/device/mem_info_vram_total` |
| GTT | 27.3 GiB (amdgpu default = ½ of RAM) | `cat /sys/class/drm/card1/device/mem_info_gtt_total` |
| Runner pool | **35.3 GiB** (Vulkan reaches VRAM + GTT) | same journal line, `total=` |

Two corrections this study pinned down (2026-09-11):

- The host file used to say "32GB DDR5" — wrong, the machine carries 64 GB
  (2×32 GB). A 32 GB reading is what the 8 GiB carve-out + 24 GiB visible RAM
  of an earlier configuration looks like; don't trust memory specs from
  memory (ask `dmidecode`/`inxi`).
- The iGPU comment used to say "~19.5 GiB usable" — that was true at 32 GB.
  GTT scales with RAM (amdgpu default = half of usable RAM), so the pool is
  now 35.3 GiB. **Implication for future models: the runner pool moves when
  RAM moves.** No `amdgpu.gttsize=` kernel param is set; the default is
  sufficient and carving more would only steal from the shared pool.

## The current model — and why its architecture changes the math

`qwen3.6:35b-a3b-coding-mtp-q4_K_M` (35.5B MoE, 8 active experts, Q4_K_M,
20.4 GiB weights). Read from `/api/show` (the daemon, not the model card, is
what enforces limits):

| field | value | meaning |
| --- | --- | --- |
| `qwen35moe.full_attention_interval` | 4 | **hybrid attention** (Qwen3-Next style): only every 4th of 41 layers (11) does full attention; the rest are linear/recurrent |
| `attention.head_count_kv` | 2 | tiny KV footprint per token (GQA) |
| `key_length`/`value_length` | 256 | head dim |
| `nextn_predict_layers` | 1 | MTP head (multi-token prediction) |
| `context_length` | 262144 | native window, no YaRN trim |

**KV cache ≈ 22 KB/token** for this model:

```
bytes/token = 2 (K+V) × full-attn-layers × kv_heads × head_dim × bytes/elem
            = 2 × 11 × 2 × 256 × 2 (f16) ≈ 22.5 KB
```

At 262144 tokens that is 5.5 GiB — measured exactly on the runner logs
(`llama_kv_cache: Vulkan0 KV buffer size = 5120.00 MiB` + a second 512 MiB
buffer). A dense-attention 35B would need ~64 GiB and could not do this; the
recurrent layers add a fixed 188 MiB (`RS buffer`) regardless of context.

Measured decode is **flat from 22k to 262k context depth** (29-31 tok/s):
the linear-attention layers make long context nearly free. Do not size
context on dense-model intuition.

## Measured baselines (0.32.3 → 0.33.3, Vulkan, 100% GPU)

| metric | value | condition |
| --- | --- | --- |
| cold load | 11-14 s | page cache cold; 20.4 GiB from NVMe (runner itself spawns in ~4 s) |
| reload | ~11 s | page cache warm |
| decode | 29-31 tok/s | flat across context depths; MTP on |
| prefill (fresh, 1520-token prompt) | ~364 tok/s | long-prompt TTFT is prefill-bound |
| MTP A/B (draft_num_predict) | 2 → **31-32 t/s**; off → 24; 4 → 22 | the GGUF ships 2 and the daemon already passes `--spec-draft-n-max 2`; **2 is optimal — do not touch** |
| full 262144 load | fits | 20.4 weights + 5.5 KV + ≤0.3 compute; ~9 GiB GTT headroom; 29 tok/s after |
| TTFT (warm, short prompt) | ~120 ms prefill | 0.33.3; metadata caching (0.32.15) roughly halved TTFT upstream |
| GPU placement | 100% GPU, `size_vram` = full model size | `ollama ps` is the check |

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

Every knob was measured; these verdicts are the record:

| setting | value | why (measured) |
| --- | --- | --- |
| `OLLAMA_CONTEXT_LENGTH` | `262144` | the vram-tier default was 32768 (≥23 GiB bracket); hybrid attention makes 256k fit with ~9 GiB headroom; decode flat |
| `OLLAMA_KEEP_ALIVE` | `1h` | kills the 11-14 s reload in interactive use; model frees itself after an hour; `-1` rejected (22 GiB would never free on a gaming box) |
| `OLLAMA_IGPU_ENABLE` | `1` | without it the iGPU is discovered then discarded; daemon silently falls back to CPU. `ollama ps` → 100% GPU is the check |
| `OLLAMA_FLASH_ATTENTION` | unset (auto) | already active (`--flash-attn auto` in the runner cmd); pinning `=1` adds nothing |
| `OLLAMA_KV_CACHE_TYPE` | unset (f16) | q8_0 would halve KV 5.5→2.7 GiB, but KV is ~4% of this model's memory — no fit gain, quality risk, and it is global to all models. Revisit only for a dense-attention model |
| `OLLAMA_NUM_PARALLEL` | unset (1) | slots multiply KV and split memory bandwidth; single-user opencode gains nothing at 2 |
| `OLLAMA_MAX_LOADED_MODELS` | unset (auto) | auto-compute already allows what fits |
| MTP `draft_num_predict` | 2 (GGUF-shipped) | measured A/B above; **do not touch** |
| `loadModels` / boot preload | not used | pulls but does not preload; boot-time preload would pin 22 GiB and slow every boot for nothing |
| `OLLAMA_GPU_OVERHEAD` | 0 (default) | makes the scheduler assume less VRAM (conservative packing) — relevant only if ollama must refuse loads while a game hogs GTT; not needed today |
| runner flags (`-b/-ub 1024`, `--context-shift`, `--keep 4`) | daemon-fixed | not user-tunable via env; no measured pathology |

Package: `unstablePkgs.ollama-vulkan` (0.33.3 at pin time). Vulkan-not-ROCm is
**re-affirmed by this study**: ROCm's known 6.42 tok/s regression on this part
(ollama#9999) still stands against the measured 29-31 tok/s Vulkan path, and
Vulkan's GTT spill is exactly what makes 256k context possible here.

BIOS carve-out (8→16 GiB) and `amdgpu.gttsize=` were considered and rejected:
decode is flat with KV resident in GTT, and carving VRAM only steals from the
shared pool the runner reaches anyway.

## opencode ↔ daemon context agreement

`modules/home/opencode.nix` declares `limit.context = 262144` for this model
(from `/api/show`, matching the GGUF). Until 2026-09-11 the daemon's default
(32768) silently overrode that per request — opencode sends no `num_ctx`, so
the client's declared limit and the daemon's enforced one disagreed by 8×.
The daemon env now sets 262144 and the two agree. When adding a local model:

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
   blast radius) and the model entry in `modules/home/opencode.nix` (shared —
   verify both hosts' drvPath deltas).
7. **Record** the measured row in the table above and date it.