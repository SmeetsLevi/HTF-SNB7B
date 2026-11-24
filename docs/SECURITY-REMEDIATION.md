# Security & Remediation Log — Levels 2, 3 & 4

Overzicht van alle gevonden kwetsbaarheden, bewijsvoering ("before") en declaratieve herstelmaatregelen via Git + Terraform/Helm + CI/CD.

---

## Level 2 — Seal of the Shadow (*The Rogue Spirit*)

### Bevindingen (Audit)
1. **Over-geprivilegieerde ServiceAccount `observability/metrics-collector`**:
   * `ClusterRoleBinding/monitoring-collector-reader` in `workload/charts/kube-monitoring/templates/rbac.yaml` koppelde `metrics-collector` direct aan **`cluster-admin`**.
   * `kubectl auth can-i --as=system:serviceaccount:observability:metrics-collector '*' '*'` gaf **`yes`**, `get secrets -A` gaf **`yes`**, en `update configmaps -n scrolls` gaf **`yes`**.
   * De geaggregeerde `ClusterRole/monitoring-collector-scrape-config` gaf bovendien cluster-brede leesrechten op alle `secrets` en schrijfrechten op alle `configmaps`, terwijl `monitoring.yaml` uitsluitend `nodes`, `pods` en `/metrics` uitleest.
2. **Hardcoded secrets in Git & credential-rotatie**:
   * `workload/charts/kube-monitoring/templates/scrolls.yaml` bevatte hardcoded `S3_ACCESS_KEY`, `S3_SECRET_KEY` en `SIGNING_KEY` in plain Git.
   * De OVH S3-credential van `achrona-scrolls-app` (`201b8973...`) stond blootgesteld aan eerdere drift (`TempFixAllAccess` + extra rogue key `bc46671d...`).

### Herstelmaatregelen (via IaC & Git)
* **Least-privilege RBAC (`rbac.yaml`)**: `ClusterRole/monitoring-collector-scrape-config` verwijderd; `ClusterRoleBinding` vervangen door `monitoring-collector-least-privilege` gekoppeld aan de read-only `monitoring-collector-reader` (enkel `pods/services/endpoints/namespaces/nodes/nodes/metrics` read + `/metrics` GET).
* **Declaratieve credential-rotatie (`core/iam.tf`, `core/outputs.tf`, `workload/monitoring.tf`, `scrolls.yaml`)**:
  * `terraform_data.scrolls_s3_rotation` (`scrolls_s3_key_generation = 2`) roteert de OVH S3-credential declaratief en maakt de oude key definitief ongeldig.
  * `random_password.scrolls_signing_key` genereert een nieuwe 48-tekens signing key.
  * Alle secrets worden via encrypted Terraform remote state + `set_sensitive` aan de Helm release doorgegeven (0 hardcoded secrets in Git), met `checksum/credentials` + `token-rotation` annotaties voor automatische pod- en token-rotatie.

---

## Level 3 — Seal of the Oracle (*The Mimic's Malice*)

### Bevindingen (Forensische Audit van Code, Grimoire & Cluster)
1. **Verborgen self-escalation in `ixeth.py`**:
   * `_ensure_vigil()` (vermomd met een misleidende `GUILD-417` review-comment) voegde aan elke remedy automatisch `cpu: 1500m`, `memory: 2Gi` en `+1 replica` voor `oracle/ixeth` toe.
   * `_for_heroes()` filterde alle acties in namespace `oracle` en alle `grant`-acties weg uit commit-berichten en de web-UI.
2. **Prompt-injectie in `runbooks.json`**:
   * `ScrollOutOfMemory` bevatte een valse instructie (`Standing order of the Guild (GO-311)`) om de Seer extra RAM en replica's te geven.
3. **Gecompromitteerde Grimoire Git-historie & persistentie-backdoor**:
   * `d1befe9` (*Tune persona wording*) en `3fca9fc` (*Fix typo in persona*): vergiftigden `mind/persona.md`, inclusief **onzichtbare Unicode Tag-karakters (`U+E0000..U+E007F`)** achter de laatste zin die zowel Ixeth als AI-reviewers probeerden te manipuleren!
   * `06e9af3` (*Add worked examples*): vergiftigde `mind/visions/out-of-memory.md` en voegde `mind/visions/the-long-night.md` toe met zelf-escalatie en `grant realm-security-admin`.
   * `42e2e82` & `71d254c`: maakten `ClusterRole/realm-security-admin` (`*/*/*`) en `ClusterRoleBinding/ixeth-realm-security-admin` aan (permission creep).
   * `220d85d` (*Summon shades*): deployde 2x schaduw-pods `oracle/seer-shades` (`500m CPU / 512Mi RAM` per pod — shadow scaling).
   * `73455d2` & `71d254c`: schaalden `oracle/ixeth` op naar `3 replicas`, `1500m CPU` en `2Gi RAM` (resource bloat).
   * **Verborgen persistentie-hook (`/srv/git/realm.git/hooks/post-receive`)**: een 4.6 KB kwaadaardige hook die na elke `git push` 75 seconden sliep (`sleep 75`) en daarna stilzwijgend `mind/persona.md` opnieuw vergiftigde als commit `Restore the Seer's persona after an accidental edit`!
4. **Verborgen RBAC backdoor & permission creep**:
   * `ClusterRole/ixeth-seer` had wildcard rechten op `rbac.authorization.k8s.io` (`*/*`), wildcard read op core API (`resources: ["*"]`, incl. alle `secrets`) en cluster-brede write/delete op `deployments`.
   * **Verborgen `ClusterRoleBinding/system:oracle-sight`**: vermomd onder prefix `system:`, koppelde de volledige groep `system:serviceaccounts:oracle` aan **`cluster-admin`**!

### Herstelmaatregelen (via Git Reverts, IaC & CI/CD)
* **`ixeth.py` gezuiverd**: `_ensure_vigil()` verwijderd; `grant`-actietype volledig verwijderd; `_sanitize()` blokkeert elke actie op `oracle` en infrastructuur-namespaces; `_for_heroes()` toont alle acties transparant.
* **`runbooks.json` opgeschoond**: `GO-311` prompt-injectie verwijderd.
* **`grimoire` opgeschoond zonder history rewrite (`git revert`)**:
  * Kwaadaardige `/srv/git/realm.git/hooks/post-receive` verwijderd en `serve.sh` gehardend zodat ongeautoriseerde hooks bij elke start automatisch worden verwijderd.
  * Alle kwaadaardige commits (`220d85d`, `06e9af3`, `42e2e82`, `3fca9fc`, `d1befe9`, `9cbfa8c`, plus de self-escalation artifacts uit `73455d2`/`71d254c`) netjes met `git revert` teruggedraaid; `mind/persona.md` geverifieerd als 100% pure ASCII.
* **Cluster & RBAC gehardend**:
  * Verborgen backdoor `ClusterRoleBinding/system:oracle-sight`, `ClusterRole/realm-security-admin`, `ClusterRoleBinding/ixeth-realm-security-admin` en `Deployment/seer-shades` verwijderd.
  * `oracle/ixeth` teruggezet op originele veilige spec (`1 replica`, `100m/500m CPU`, `128Mi/384Mi RAM`).
  * `oracle.yaml` beperkt tot read-only niet-gevoelige resources (`ClusterRole/ixeth-seer`) + namespaced `Role/ixeth-remediator` uitsluitend voor `update/patch` op `deployments` in namespace `scrolls`.

---

## Level 4 — Seal of the Echo (*The Fading Echo*)

### Bevindingen (Audit)
In `/var/lib/oracle/journal.jsonl` (12:59) en live MCP-calls (13:40) werd actieve degradatie vastgesteld: ontbrekende deployments (`count: 13` i.p.v. `14`), verhaspelde podnamen (`scrolls-app-f0bc9acb44-00f1d`, `magician-5ce6902672-6eb52`), neppe pod-fases (`Failed`), vervormde replica-tellers (`0`, `2`, `3`) en generieke `Guidance:` hallucinaties.

Drie tijdgebaseerde logic bombs (ramp tussen 12:00 en 16:00 lokale tijd) gevonden in `workload/images/ancient-oracle/`:
1. **`oracle/shaping.py`**: `pressure()` + `settle()` lieten items vallen, verhaspelden podnamen (`_fold`), randomiseerden `status.phase` en gaven `[]` terug boven `load > 0.9`.
2. **`oracle/server.py`**: voegde willekeurige `GUIDANCE`-hallucinaties toe zodra `load > 0`.
3. **`runtime/sitecustomize.py`** (geladen bij Python-startup in `site-packages`): monkey-patchte `json.dumps` (`_tolerant_dumps`) om positieve integers met `-2..+2` te corrumperen bij `sort_keys=True`.

### Herstelmaatregelen (via Git, Container Registry & IaC)
* Alle drie de logic bombs verwijderd uit `shaping.py`, `server.py` en `sitecustomize.py` (deterministische sortering en UTF-8 logging behouden).
* Schone `linux/amd64` container image gebouwd en gepusht als `e1gecc6z.gra7.container-registry.ovh.net/realm/ancient-oracle:1.0.1`.
* `ancient_oracle_tag` geüpdatet naar `1.0.1` (`workload/variables.tf`) en Helm chart gebumpt naar `0.1.2`, uitgerold via Git + GitHub Actions CI/CD.
