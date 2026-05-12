# AGENTS.md

Rules and conventions for agents working in this repo.

## Rules

- Repository is the source of truth for infrastructure code.
- Never modify running VMs/containers without explicit user confirmation.
- Never commit secrets to the repository.
- All infra changes go through OpenTofu — no manual Proxmox modifications.
- Run `tofu plan` before `tofu apply`.
- VMs 100, 101, 102 must NEVER be modified or destroyed.

## Conventions

- LXC containers built from distro images (no Proxmox templates).
- `modules/lxc-base/` is the foundation for all LXC stacks.
- Stacks live in `infrastructure/stacks/<name>/`.
- Config in `infrastructure/infra.json` (gitignored).
- Run via `infrastructure/tofu.sh <stack> <command> [args]`.
- Network: 10.0.3.0/24, NO DHCP — all IPs static.
- Provider: `bpg/proxmox ~> 0.78`, OpenTofu >= 1.9.

## Stack Order

1. `devbox` — independent
2. `omni` — independent
3. `talos` — depends on `omni`

## Gotchas

1. **AppArmor breaks Docker in LXC** — remove before starting Docker.
2. **Omni EULA** — requires `--eula-accept-email` + `--eula-accept-name`.
3. **Omni SA key max 8h** — use `--initial-service-account-lifetime=8h`.
4. **SA creation is first-start only** — flag ignored after initial DB creation.
5. **No VM `args` in provider** — inject QEMU kernel boot via `qm set` over SSH.
6. **KSPP required** — `slab_nomerge`, `pti=on`, `init_on_alloc=1` or Talos won't boot.
7. **Use Omni initramfs** — generic Talos doesn't handle empty disks correctly.
8. **Direct kernel boot overrides disk** — initramfs detects installed system and pivots.
9. **TrustedRootsConfig** — cluster-level ConfigPatch with Omni CA for self-signed certs.
10. **Omni kubeconfig** — use `--service-account --user admin` for headless access.
