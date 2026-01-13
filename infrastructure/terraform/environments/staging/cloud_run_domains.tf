module "cloud_run_domain_mappings" {
  source     = "../../modules/cloud_run_domain_mappings"
  project_id = var.project_id
  region     = var.region
  domains = {
    for key, domain in local.domain_mappings :
    domain => local.service_names[key]
  }

  depends_on = [
    module.admin_service,
    module.agent_customization,
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
