# Contributing

Thanks for your interest in media-upscaler.

## Setup

```bash
./scripts/setup.sh          # installs Real-ESRGAN venv + Video2X into tools/
./scripts/check-gpu.sh      # verify GPU readiness (CUDA + Vulkan)
./scripts/download-test-media.sh  # fetch public-domain test fixtures
```

## Testing

```bash
./scripts/test.sh                   # fast suite (~30 s, no GPU inference)
./scripts/test.sh --integration     # full suite with real GPU inference
bash -n scripts/*.sh                # shell lint
```

Run the fast suite before every commit. Run `--integration` before any PR that touches inference paths or quality thresholds.

## Commit convention

```
#type, what; what; what
```

`type` = `add` / `fix` / `doc` / `refactor` / `stabilize` / `edit`. Clauses are semicolon-separated. No Co-Authored-By footer.

Examples:
```
#fix, upscale-video: -q auto no-GPU path exited 1 under pipefail
#add, quality gate: PSNR/SSIM harness + assert_quality in test.sh
#doc, readme: add xhigh and auto to video preset table
```

## Branch and PR flow

- Work off `main`. Short-lived feature branches are fine; rebase before merging.
- Keep PRs focused: one feature or fix per PR.
- All tests must pass. The integration suite is the bar for anything touching inference.
- Update docs in the same commit as code — never lag.

## Architecture rules

- Shell scripts orchestrate; Python computes. No awk float math or bash arithmetic beyond plain integer threshold comparisons (`[ "$x" -ge N ]`). New numeric logic goes in a `.py` script.
- Fail fast: validate at script entry, error to stderr with non-zero exit.
- Exit codes are contracts (0 = success, 1 = validation fail, 2 = dependency/setup missing, 3 = inference error).

## Contribution licensing

By submitting a pull request you agree that your contribution is licensed under the same MIT License that covers this project (inbound = outbound).
