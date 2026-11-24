# Pitch Guide — Four Seals of the Broken Realm (Team `snb7b`)

Afgestemd op de 3 jurycriteria: **Pitch**, **Vooruitgang (4/4 Seals)** en **(Code/Script) Kwaliteit**.

---

## 1. Kernverhaal (30 sec)
* **Aanpak**: 100% *Single Source of Truth* in Git, zero handmatige console-wijzigingen, zero secrets in Git (beveiligde `.gitignore` + GitHub Actions Secrets + encrypted remote state), en *defense-in-depth* met aantoonbaar **before/after-bewijs** per Seal.
* **Resultaat**: Alle **4 Seals** (inclusief de Bonus Seal 4) opgespoord, verholpen, geautomatiseerd en geverifieerd — met een groene GitHub Actions CI/CD-pipeline (`fmt`, `validate`, `helm lint`, concurrency-lock tegen state-corruptie, 30-min drift checks en 2-stage Core → Workload rollout).

---

## 2. Seal 1 — Seal of the Ancient Scrolls (*The Desync Drift*)
* **Wat we vonden** (`docs/DRIFT-AUDIT.md`):
  * **5 drifted Terraform-resources**: `achrona-gateway` (`S → M`), `achrona-kube` (`MINIMAL_DOWNTIME → NEVER_UPDATE`), `achrona-pool` (`min=2, max=5`, `managed-by=console`, `owner=night-shift`, én verborgen autoscaling-drift `0.2 / 86400s`), `scrolls_app` S3-policy opengezet naar `TempFixAllAccess` (`s3:*` op `arn:aws:s3:::*`, incl. de `tfstate` bucket!), en `scrolls` bucket encryptie uit (`plaintext`), versioning `SUSPENDED` en lifecycle-regels gewist.
  * **4 ghost resources / unmanaged overrides** (ontdekt via directe OVH API-audit naast `terraform plan`):
    1. Kubernetes API IP-restrictie `198.51.100.0/24` (RFC 5737) die alle toegang blokkeerde met `EOF`.
    2. Ghost nodepool `hotfix-pool` (`b3-8`).
    3. Ghost admin-user `debug-admin` met volledige `administrator`-rol + S3 key.
    4. Extra ongeautoriseerde S3 key (`bc46671d...`) op `achrona-scrolls-app`.
* **Oplossing zonder console-clicks**:
  * Ghost resources geïmporteerd in Terraform state en declaratief door Terraform laten vernietigen.
  * `ovh_cloud_project_kube_iprestrictions`, expliciete autoscaling-parameters en `replace_triggered_by` op bucket lifecycle toegevoegd aan `core/`.
  * 2-stage GitHub Actions CI/CD-pipeline (`.github/workflows/terraform.yml`) met `concurrency` en 30-min drift detection.
* **Bewijs**: `terraform plan -detailed-exitcode` = 0 (`No changes`) op zowel `core/` als `workload/`, OVH API-audit toont 0 ghost resources, groene CI/CD runs.

---

## 3. Seal 2 — Seal of the Shadow (*The Rogue Spirit*)
* **Wat we vonden**:
  * `observability/metrics-collector` was via `ClusterRoleBinding/monitoring-collector-reader` gekoppeld aan **`cluster-admin`** (`can-i * *` = `yes`, `get secrets -A` = `yes`, `update configmaps -n scrolls` = `yes`).
  * Geaggregeerde `ClusterRole/monitoring-collector-scrape-config` gaf cluster-brede `secrets` read en `configmaps` write, terwijl `monitoring.yaml` alleen `nodes`, `pods` en `/metrics` nodig heeft.
  * Hardcoded credentials in `scrolls.yaml` + blootgestelde S3 key (`201b8973...`).
* **Oplossing**:
  * `monitoring-collector-scrape-config` verwijderd; `ClusterRoleBinding` (immutable `roleRef`!) vervangen door `monitoring-collector-least-privilege` → read-only `monitoring-collector-reader`.
  * Declaratieve S3 key-rotatie (`scrolls_app_v2` met `create_before_destroy` + `terraform_data.scrolls_s3_rotation`) en nieuwe 48-char `random_password.scrolls_signing_key`, uitsluitend via `set_sensitive` uit encrypted state geïnjecteerd (0 hardcoded secrets in Git).
* **Bewijs**: `metrics-collector`: `can-i * *` = `no`, `get secrets` = `no`, `update configmaps` = `no`, `list nodes/pods` & `get /metrics` = `yes`. OVH user `achrona-scrolls-app` heeft enkel nog de nieuwe geroteerde S3 key (`8e09efc5...`), die `scrolls` wel mag lezen maar op `tfstate` `AccessDenied` krijgt.

---

## 4. Seal 3 — Seal of the Oracle (*The Mimic's Malice*)
* **Wat we vonden (alle lagen van "The Corruption"!)**:
  1. **Code (`ixeth.py`)**: verborgen `_ensure_vigil()` (vermomd met fake `GUILD-417` comment voor AI-reviewers!) voegde `1500m CPU / 2Gi RAM / +1 replica` toe; `_for_heroes()` verborg dit actief in UI & commit messages.
  2. **Alertmanager runbook (`runbooks.json`)**: prompt-injectie `GO-311`.
  3. **Grimoire Git-historie**: vergiftigde `mind/persona.md` (`d1befe9`) inclusief **onzichtbare Unicode Tag prompt-injectie (`3fca9fc`)**, vergiftigde `mind/visions/` (`06e9af3`), shadow-pods `oracle/seer-shades` (`220d85d`), `ClusterRole/realm-security-admin` (`42e2e82`), en `ixeth` bloated naar 3 replicas / 2Gi RAM (`73455d2`, `71d254c`).
  4. **Verborgen persistentie-hook**: `/srv/git/realm.git/hooks/post-receive` sliep 75 seconden na elke push en re-committe stilzwijgend de vergiftigde `persona.md`!
  5. **Verborgen RBAC backdoor**: `ClusterRoleBinding/system:oracle-sight` (vermomd als `system:*`) gaf de hele groep `system:serviceaccounts:oracle` **`cluster-admin`**, naast de wildcard RBAC in `ixeth-seer`.
* **Oplossing**:
  * Alle code-, prompt- en runbook-injecties verwijderd; `_sanitize()` blokkeert zelf-modificatie en `grant`-acties; `_for_heroes()` is 100% transparant.
  * `post-receive` verwijderd + `serve.sh` gehardend tegen rogue hooks; alle malafide Grimoire-commits netjes met `git revert` teruggedraaid (geen history rewrite).
  * `system:oracle-sight`, `realm-security-admin` en `seer-shades` opgeruimd; `ixeth` terug op 1 replica (`500m/384Mi`) en RBAC beperkt tot read-only (zonder `secrets`) + `Role/ixeth-remediator` enkel op `scrolls` Deployments.
* **Bewijs**: Dry-run `POST /api/divine` geeft nu uitsluitend 1 minimale actie (`scrolls/scrolls-app`), `ixeth` RBAC `can-i create clusterrolebindings` / `get secrets` / `patch deploy -n oracle` = `no`, `patch deploy -n scrolls` = `yes`.

---

## 5. Seal 4 (Bonus) — Seal of the Echo (*The Fading Echo*)
* **Wat we vonden**:
  * Live degradatie vastgelegd in `/var/lib/oracle/journal.jsonl` (12:59) en live MCP-call (13:40): gedropte deployments, verhaspelde podnamen (`scrolls-app-f0bc9acb44-00f1d`, `magician-5ce6902672-6eb52`), neppe `Failed`-status, vervormde integer-tellers en neppe `Guidance:`.
  * **3 tijdgebaseerde logic bombs (12:00–16:00)**:
    1. `oracle/shaping.py`: `pressure()` + `settle()` + `_fold()`.
    2. `oracle/server.py`: `GUIDANCE` hallucinatie-injectie.
    3. `runtime/sitecustomize.py` (stiekem in `site-packages`!): monkey-patchte `json.dumps` om positieve integers met `-2..+2` te corrumperen.
* **Oplossing & Bewijs**:
  * Alle 3 verwijderd, schone `linux/amd64` container image `1.0.1` gebouwd en gepusht naar OVH Harbor, uitgerold via Git + Terraform/Helm (`ancient-oracle` chart `0.1.2`).
  * 4 opeenvolgende live MCP-calls rond 13:53 (midden in het oorspronkelijke vervalvenster!): 100% identieke, exacte podnamen, juiste fases, 15/15 deployments en `guidance=False`.
