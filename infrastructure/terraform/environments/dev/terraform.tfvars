project_id      = "liive-dev"
region          = "europe-west1"
firestore_location = "europe-west1"
billing_account = "01F039-B3AA01-B0E817"
enable_agent_tools_redis_cache = true
typesense_host = "fl497zkby30xopqip-1.a1.typesense.net"
custom_domain_base = "liive.app"

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
      OPS_PHONE                = "+15005550006"
      OPS_EMAIL                = "ops-dev@ordering-intelligence.test"
      TWILIO_MESSAGING_NUMBER  = "+13292120971"
    }
  }
}
