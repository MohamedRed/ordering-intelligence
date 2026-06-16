project_id      = "ordering-intelligence-staging"
region          = "us-central1"
billing_account = "013632-2013D4-83320F"

image_registry_project = "ordering-intelligence"

custom_domain_base = "liive.app"

order_service_lb_hostname         = "staging-order-service.liive.app"
order_service_lb_certificate_mode = "MANAGED"
order_service_lb_managed_domains  = ["staging-order-service.liive.app"]

admin_service_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
]

agent_customization_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
]

onboarding_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
  "https://staging-driver.liive.app",
]

notification_service_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
  "https://staging-consumer.liive.app",
  "https://staging-driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

dispatch_service_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
  "https://staging-consumer.liive.app",
  "https://staging-driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

channel_gateway_cors_origins = [
  "https://staging-admin.liive.app",
  "https://staging-business.liive.app",
  "https://staging-consumer.liive.app",
  "https://staging-driver.liive.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]
