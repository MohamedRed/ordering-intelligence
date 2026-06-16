project_id      = "ordering-intelligence-prod"
region          = "us-central1"
billing_account = "013632-2013D4-83320F"

image_registry_project = "ordering-intelligence"

custom_domain_base = "liive.app"

order_service_lb_hostname         = "order-service.liive.app"
order_service_lb_certificate_mode = "MANAGED"
order_service_lb_managed_domains  = ["order-service.liive.app"]

agent_customization_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
]
