locals {
  dns_name = var.domain == "" ? "" : (endswith(var.domain, ".") ? var.domain : "${var.domain}.")

  expected_record_keys = {
    for item in flatten([
      for domain, types in var.expected_record_types : [
        for record_type in types : {
          key    = "${domain}|${record_type}"
          domain = domain
          type   = record_type
        }
      ]
      ]) : item.key => {
      domain = item.domain
      type   = item.type
    }
  }

  resource_record_sets = {
    for key, meta in local.expected_record_keys :
    key => {
      name = endswith(meta.domain, ".") ? meta.domain : "${meta.domain}."
      type = meta.type
      ttl  = var.ttl
      rrdatas = distinct(flatten([
        for record in try(var.resource_records[meta.domain], []) :
        can(tolist(record.rrdata)) ? tolist(record.rrdata) : [tostring(record.rrdata)]
        if record.type == meta.type
      ]))
    }
  }

  extra_record_sets = {
    for record in var.extra_records :
    "${record.name}|${record.type}" => {
      name    = endswith(record.name, ".") ? record.name : "${record.name}."
      type    = record.type
      ttl     = try(record.ttl, var.ttl)
      rrdatas = record.rrdatas
    }
  }

  record_sets = merge(local.resource_record_sets, local.extra_record_sets)
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
