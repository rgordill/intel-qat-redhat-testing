# HAProxy with `USE_ENGINE=1` on RHEL 9 (Red Hat SRPM only)

The HAProxy binary shipped in RHEL AppStream is typically built **without** `USE_ENGINE=1`, so the `ssl-engine` global directive and OpenSSL engine usage are unavailable. To use an OpenSSL engine (for example with Intel QAT), rebuild HAProxy from the **official Red Hat source RPM** with `USE_ENGINE=1` added to the `%build` `make` flags.

This project does **not** use third-party HAProxy packages (for example RPM Fusion). The SRPM must come from Red Hat:

- Enable the AppStream **source** repository. **RHSM / laptop**: Repo ID like  
  `rhel-9-for-x86_64-appstream-source-rpms`. **AWS/RHEL with RHUI**: IDs look like  
  `rhui-rhel-9-for-x86_64-appstream-source-rhui-rpms` — run  
  `subscription-manager repos --list-available | grep -i source | grep -i appstream`  
  and enable the line matching your architecture.
- On other CPU architectures, substitute `aarch64`, `ppc64le`, or `s390x` for `x86_64` in the Repo ID.

## Manual procedure (same steps as the `haproxy_qat_build` role)

1. **Subscription**  
   Register the host with RHSM (activation key or equivalent) so `dnf` and `subscription-manager` can access BaseOS, AppStream, and **source** repos.

2. **Enable the AppStream source repo** (example x86_64):

   ```bash
   sudo subscription-manager repos --enable rhel-9-for-x86_64-appstream-source-rpms
   ```

3. **Install build tooling**

   ```bash
   sudo dnf install -y rpm-build dnf-plugins-core
   ```

4. **Download the official HAProxy SRPM** (from enabled Red Hat repos, not rpmfusion):

   ```bash
   mkdir -p /var/tmp/haproxy-qat-src
   sudo dnf download --source --refresh -y --destdir /var/tmp/haproxy-qat-src haproxy
   ```

5. **Install the SRPM into an rpmbuild tree** (example topdir):

   ```bash
   sudo mkdir -p /var/lib/qatbench/rpmbuild/{SPECS,SOURCES,BUILD,RPMS,SRPMS,BUILDROOT}
   sudo rpm -ivh --replacepkgs --define "_topdir /var/lib/qatbench/rpmbuild" /var/tmp/haproxy-qat-src/haproxy-*.src.rpm
   ```

6. **Patch `haproxy.spec`**  
   In `%build`, locate the `make` invocation that sets `USE_OPENSSL=…` and add **`USE_ENGINE=1`** to the same flag list (same pattern as the Ansible `replace` task in `roles/haproxy_qat_build/tasks/main.yml`).

7. **Install build dependencies and rebuild**

   ```bash
   sudo dnf builddep -y /var/lib/qatbench/rpmbuild/SPECS/haproxy.spec
   sudo rpmbuild -bb --define "_topdir /var/lib/qatbench/rpmbuild" /var/lib/qatbench/rpmbuild/SPECS/haproxy.spec
   ```

   If `dnf builddep` reports missing packages, you may need additional **Red Hat** repos (for example CodeReady Builder for some `-devel` RPMs). Set `haproxy_qat_build_rhsm_extra_repo_ids` in Ansible; do not add rpmfusion.

8. **Install the built RPMs** (exclude debuginfo unless you want them):

   ```bash
   sudo dnf install -y /var/lib/qatbench/rpmbuild/RPMS/x86_64/haproxy-*.rpm
   ```

   Adjust the architecture directory if not x86_64.

9. **Verify**

   ```bash
   haproxy -vv 2>&1 | grep -i USE_ENGINE
   ```

## Ansible

Role: `ansible/roles/haproxy_qat_build`  
Defaults leave **`haproxy_qat_build_rhsm_source_repo_ids`** empty so the role discovers AppStream source Repo IDs from `subscription-manager`, then falls back to RHUI + CDN naming if needed. Override with explicit IDs on Satellite. Optional **`haproxy_qat_build_rhsm_extra_repo_ids`** lists **additional Red Hat** repo IDs (for example CRB) if `builddep` requires it.

`playbooks/deploy_benchmark.yml` runs this role when `enable_qat` is true, before `haproxy_server`. A marker file under `/var/lib/qatbench/` prevents `haproxy_server` from re-installing the pinned distro `haproxy-2.8*` package over your rebuilt RPM.
