# haproxy_qat_build

Rebuilds HAProxy from the **Red Hat AppStream source** SRPM with `USE_ENGINE=1` so OpenSSL engine directives (e.g. QAT) work.

- SRPM source: **`dnf download --source haproxy`** after enabling AppStream **source** repos (`subscription-manager` discovery prefers RHUI IDs on AWS/Azure; CDN IDs otherwise).
- **Not** RPM Fusion or other third-party HAProxy sources.

See **`docs/HAPROXY_USE_ENGINE_BUILD.md`** for the manual equivalent and architecture-specific repo names.

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `haproxy_qat_build_rhsm_source_repo_ids` | `[]` (auto) | Non-empty: explicit Repo IDs. Empty: parse `subscription-manager repos --list-available`, else **`haproxy_qat_build_rhsm_source_repo_ids_fallback`** (RHUI then CDN) |
| `haproxy_qat_build_rhsm_source_repo_ids_fallback` | RHUI + CDN patterns | Used only when the explicit list is empty and discovery finds no matching Repo ID |
| `haproxy_qat_build_rhsm_extra_repo_ids` | `[]` | Extra **Red Hat** repos if `dnf builddep` fails (e.g. CodeReady Builder) |
| `haproxy_qat_build_rpmbuild_dir` | `/var/lib/qatbench/rpmbuild` | `_topdir` for `rpm`/`rpmbuild` |
| `haproxy_qat_build_work_dir` | `/var/lib/qatbench/haproxy-qat-src` | Where `dnf download --source` writes the SRPM |
| `haproxy_qat_build_marker_path` | `/var/lib/qatbench/haproxy-use-engine-from-src` | Written after install; `haproxy_server` skips distro `dnf` when this exists |
| `haproxy_qat_build_force` | `false` | Set `true` to rebuild even when marker exists and `haproxy -vv` already shows `USE_ENGINE` |

## Resuming after a failure (`--start-at-task`)

Repo discovery and `rhsm_repository` live in `tasks/source_repo_phase.yml`, imported once from `main.yml`. Start there so `rebuild_context` runs again (marker / `haproxy -vv` / `do_rebuild`) before discovery:

```bash
ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml \
  --start-at-task 'AppStream source repos discover + RHSM enable (resume here after repo failures)'
```

Match that task **name** string (Ansible treats `--start-at-task` as a substring match against each task name).

## Requirements

- RHEL 9+ with working RHSM and rights to enable AppStream **source** repos.
- Run after `rhel_subscription` (or any registration that makes those repos available).
- AppStream **source** repos are enabled with **`subscription-manager repos --enable`** (`ansible.builtin.command`): `community.general.rhsm_repository` rejects some RHUI Repo IDs that the CLI accepts.
- Other steps use `ansible.builtin` plus `command`: `dnf download --source`, `rpm -ivh`, `dnf builddep`, `rpmbuild`.
