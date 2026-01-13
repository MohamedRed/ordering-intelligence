locals {
  dns_name = var.domain == "" ? "" : (endswith(var.domain, ".") ? var.domain : "${var.domain}.")

  mapping_records = flatten([
    for domain, records in var.resource_records : [
      for record in records : {
        name    = record.name
        type    = record.type
        ttl     = var.ttl
        rrdatas = can(tolist(record.rrdata)) ? tolist(record.rrdata) : [tostring(record.rrdata)]
      }
    ]
  ])

  extra_records = [
    for record in var.extra_records : {
      name    = record.name
      type    = record.type
      ttl     = try(record.ttl, var.ttl)
      rrdatas = record.rrdatas
    }
  ]

  combined_records = concat(local.mapping_records, local.extra_records)

  record_groups = {
    for record in local.combined_records :
    "${record.name}|${record.type}" => record...
  }

  record_sets = {
    for key, records in local.record_groups :
    key => {
      name    = records[0].name
      type    = records[0].type
      ttl     = records[0].ttl
      rrdatas = distinct(flatten([for r in records : r.rrdatas]))
    }
  }
}

resource "google_dns_managed_zone" "this" {
  count       = var.enabled ? 1 : 0
  project     = var.project_id
  name        = var.zone_name
  dns_name    = local.dns_name
  description = var.description
}

resource "google_dns_record_set" "records" {
  for_each = var.enabled ? local.record_sets : {}

  project      = var.project_id
  managed_zone = google_dns_managed_zone.this[0].name
  name         = each.value.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}
