# Level 1 — Drift & Ghost Resource Audit (`core/`)

Audit uitgevoerd op de live OVHcloud Public Cloud omgeving (`5d455b6299b540a392d98e73f3ab632c`) via `terraform plan` en directe OVH API-inspectie (read-only).

## 1. Geïdentificeerde Drift op Terraform-managed resources

| Resource | Gewenste staat (IaC) | Live afwijking (Console/Desync) | Beoordeling | Actie |
|---|---|---|---|---|
| `ovh_cloud_gateway.this` (`achrona-gateway`) | `model = "S"` | Gewijzigd naar `model = "M"` | Onnodige kostenverhoging / ongeautoriseerde override | Terugdraaien naar `"S"` via Terraform |
| `ovh_cloud_project_kube.this` (`achrona-kube`) | `update_policy = "MINIMAL_DOWNTIME"` | Gewijzigd naar `"NEVER_UPDATE"` | Onveilig: blokkeert beveiligingsupdates | Terugdraaien naar `"MINIMAL_DOWNTIME"` via Terraform |
| `ovh_cloud_project_kube_nodepool.default` (`achrona-pool`) | `min=1, max=3`, labels `managed-by=terraform`, autoscaling threshold `0.5` / unneeded `600s` | `min=2, max=5`, labels `managed-by=console`, `owner=night-shift`, threshold `0.2`, unneeded `86400s` | Ongeautoriseerde handmatige scaling- & label-override; autoscaling-parameters expliciet vastgelegd in `core/kube.tf` | Vastleggen in IaC en terugdraaien via Terraform |
| `ovh_cloud_project_user_s3_policy.scrolls_app` | Least-privilege `ScrollsReadWrite` op uitsluitend `achrona-5d455b62-scrolls` | Vervangen door `TempFixAllAccess` (`s3:*` op `arn:aws:s3:::*`, incl. `tfstate`-bucket!) | Kritiek beveiligingsrisico | Direct terugdraaien naar least-privilege policy via Terraform |
| `ovh_cloud_storage_object_bucket.scrolls` (`achrona-5d455b62-scrolls`) | `encryption = AES256`, `versioning = ENABLED`, 2 lifecycle rules | `encryption = plaintext` (uitgeschakeld), `versioning = SUSPENDED`, lifecycle rules verwijderd | Kritiek beveiligings- en dataverliesrisico (bucket bevat 0 objecten) | Herstellen via Terraform (+ `replace_triggered_by` op lifecycle configuration) |

## 2. Geïdentificeerde Ghost Resources & Unmanaged Overrides (buiten Terraform state)

| Resource / Override | Details | Beoordeling | Actie (via IaC, geen console-edits) |
|---|---|---|---|
| Kubernetes API IP Restrictions | `["198.51.100.0/24"]` (RFC 5737 TEST-NET-2) toegevoegd aan `achrona-kube` | Blokkeerde alle toegang (`kubectl`, Terraform `workload/`, CI/CD) met TLS/EOF | Declaratieve `ovh_cloud_project_kube_iprestrictions` toegevoegd aan `core/kube.tf` |
| Ghost Nodepool `hotfix-pool` | ID `bda7e013-42e1-43de-9370-60692ab37977` (node `hotfix-pool-node-094e4b`, 1x `b3-8`, geen autoscale/anti-affinity/labels) | Ongeautoriseerde shadow-capaciteit buiten IaC | Geïmporteerd in Terraform state en via IaC/pipeline verwijderd |
| Ghost OVH User `debug-admin` | ID `1014687` (`user-RM58C9jMFXkR`), rol **`administrator`**, S3 access key `f19ff5f0859f41798a2a94200fc8d00f` | Kritiek IAM-lek / backdoor admin-account | Geïmporteerd in Terraform state en via IaC/pipeline verwijderd |
| Ghost S3 Credential op `achrona-scrolls-app` | Extra ongeautoriseerde S3 key `bc46671d07e5440698f86321b7846020` op user `1013967` | Onbeheerde credential naast Terraform-managed key | Geïmporteerd in Terraform state en via IaC/pipeline verwijderd |

## 3. Preventie & Automatisering

* **Single Source of Truth**: Alle infrastructuur (`core/` en `workload/`) staat versiebeheerd in Git.
* **CI/CD Pipeline (`.github/workflows/terraform.yml`)**:
  * Valideert `terraform fmt -check`, `terraform validate`, `helm lint` en `terraform plan` bij elke PR en push.
  * Voert periodieke drift-detectie uit (elke 30 minuten via `schedule`).
  * Gebruikt `concurrency` (`cancel-in-progress: false`) om gelijktijdige state-mutaties te voorkomen.
  * Rolt wijzigingen automatisch uit na merge op `main` met post-apply drift verificatie.
