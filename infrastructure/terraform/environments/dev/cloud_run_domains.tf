module "cloud_run_domain_mappings" {
  source     = "../../modules/cloud_run_domain_mappings"
  project_id = var.project_id
  region     = var.region
  domains = var.enable_cloud_run_domain_mappings ? {
    for key, domain in local.domain_mappings :
    domain => local.service_names[key]
  } : {}

  depends_on = [
    module.admin_service,
    module.agent_customization_service,
    module.agent_tools,
    module.agent_webhooks,
    module.channel_gateway,
    module.channel_comms,
    module.customer_profile,
    module.delivery_service,
    module.dispatch_service,
    module.menu_ingestion,
    module.notification_service,
    module.onboarding_service,
    module.order_service,
    module.payments_service,
    module.recommendation,
    module.typesense_indexer,
    module.wait_time_service
  ]
}

module "cloud_dns_zone" {
  source      = "../../modules/cloud_dns_zone"
  project_id  = var.project_id
  zone_name   = var.cloud_dns_zone_name
  domain      = local.dns_domain
  description = local.dns_domain != "" ? "Managed zone for ${local.dns_domain}" : "Managed zone"
  enabled     = var.enable_cloud_dns && local.dns_domain != ""

  resource_records = {
    for domain, records in module.cloud_run_domain_mappings.resource_records :
    domain => try(tolist(records), [])
  }
  extra_records         = local.dns_extra_records
  expected_record_types = local.expected_record_types
}
