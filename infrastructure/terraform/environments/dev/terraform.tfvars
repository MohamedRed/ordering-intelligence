project_id                       = "liive-dev"
region                           = "europe-west1"
firestore_location               = "europe-west1"
billing_account                  = "01F039-B3AA01-B0E817"
enable_agent_tools_redis_cache   = true
typesense_host                   = "fl497zkby30xopqip-1.a1.typesense.net"
custom_domain_base               = "liive.app"
custom_domain_prefix             = "dev-"
enable_cloud_dns                 = true
enable_cloud_run_domain_mappings = true

admin_service_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:5173",
  "http://localhost:8080",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
]

agent_customization_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:5173",
  "http://localhost:8080",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
]

onboarding_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:5173",
  "http://localhost:8080",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
  "https://liive-dev-driver.web.app",
]

notification_service_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:4001",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://127.0.0.1:4000",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
  "https://liive-dev-consumer.web.app",
  "https://liive-dev-driver.web.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

dispatch_service_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:4001",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://127.0.0.1:4000",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
  "https://liive-dev-consumer.web.app",
  "https://liive-dev-driver.web.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

delivery_service_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:4001",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://127.0.0.1:4000",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
  "https://liive-dev-consumer.web.app",
  "https://liive-dev-driver.web.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

channel_gateway_cors_origins = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:4001",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://localhost:65269",
  "http://127.0.0.1:4000",
  "https://liive-dev-admin.web.app",
  "https://liive-dev-business.web.app",
  "https://liive-dev-consumer.web.app",
  "https://liive-dev-driver.web.app",
  "https://telegram-mini-oi2.web.app",
  "https://1457874399339347988.discordsays.com",
]

cloud_run_overrides = {
  notification_service = {
    min_scale             = 0
    max_scale             = 5
    container_concurrency = 40
    timeout_seconds       = 120
    cpu                   = "1000m"
    memory                = "512Mi"
    startup_cpu_boost     = true
    env_overrides = {
      OPS_PHONE               = "+15005550006"
      OPS_EMAIL               = "ops-dev@ordering-intelligence.test"
      TWILIO_MESSAGING_NUMBER = "+13292120971"
    }
  }
  dispatch_service = {
    image = "europe-west1-docker.pkg.dev/liive-dev/services/dispatch-service:64b0d87a"
  }
  onboarding_service = {
    image = "europe-west1-docker.pkg.dev/liive-dev/services/onboarding-service:c976d7ac"
  }
}
