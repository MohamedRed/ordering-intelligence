project_id      = "ordering-intelligence-prod"
region          = "us-central1"
billing_account = "013632-2013D4-83320F"

image_registry_project = "ordering-intelligence"

custom_domain_base = "liive.app"

order_service_lb_hostname         = "order-service.liive.app"
order_service_lb_certificate_mode = "MANAGED"
order_service_lb_managed_domains  = ["order-service.liive.app"]

admin_service_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
]

agent_customization_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
]

onboarding_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
  "https://driver.liive.app",
]

notification_service_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
  "https://consumer.liive.app",
  "https://driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

dispatch_service_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
  "https://consumer.liive.app",
  "https://driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

channel_gateway_cors_origins = [
  "https://admin.liive.app",
  "https://business.liive.app",
  "https://consumer.liive.app",
  "https://driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]
