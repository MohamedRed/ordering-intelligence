terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

module "core" {
  source             = "../../modules/core"
  project_id         = var.project_id
  region             = var.region
  firestore_location = var.firestore_location
  billing_account    = var.billing_account
  run_service_accounts = [
    module.admin_service_sa.email,
    module.agent_customization_sa.email,
    module.agent_tools_sa.email,
    module.wait_time_service_sa.email,
    module.dispatch_service_sa.email,
    module.delivery_service_sa.email,
    module.order_service_sa.email,
    module.menu_ingestion_sa.email,
    module.notification_service_sa.email,
    module.onboarding_service_sa.email,
    module.payments_service_sa.email,
    module.agent_webhooks_sa.email,
    module.channel_gateway_sa.email,
    module.channel_comms_sa.email,
    module.typesense_indexer_sa.email
  ]
}

locals {
  service_names = {
    admin_service        = "admin-service"
    agent_customization  = "agent-customization-service"
    agent_tools          = "agent-tools"
    order_service        = "order-service"
    dispatch_service     = "dispatch-service"
    delivery_service     = "delivery-service"
    menu_ingestion       = "menu-ingestion"
    notification_service = "notification-service"
    onboarding_service   = "onboarding-service"
    payments_service     = "payments-service"
    agent_webhooks       = "agent-webhooks"
    channel_gateway      = "channel-gateway"
    channel_comms        = "channel-comms"
    customer_profile     = "customer-profile-service"
    recommendation       = "recommendation-service"
    wait_time_service    = "wait-time-service"
    typesense_indexer    = "typesense-indexer"
  }

  project_number = tostring(data.google_project.current.number)

  image_registry_project = var.image_registry_project != "" ? var.image_registry_project : var.project_id
  image_registry_host    = "${var.region}-docker.pkg.dev"

  custom_domain_prefix = var.custom_domain_prefix != "" ? var.custom_domain_prefix : (
    var.environment_name == "prod" ? "" : "${var.environment_name}-"
  )
  skip_onboarding_domain_mapping = false

  default_custom_domain_exclusions = concat(
    ["agent_tools", "agent_webhooks"],
    length(var.order_service_lb_managed_domains) > 0 ? ["order_service"] : []
  )

  custom_domain_service_keys = length(var.custom_domain_service_keys) > 0 ? var.custom_domain_service_keys : [
    for key in keys(local.service_names) : key
    if !contains(local.default_custom_domain_exclusions, key)
  ]

  default_service_domains = {
    for key, name in local.service_names :
    key => var.enable_cloud_run_domain_mappings && var.custom_domain_base != "" && contains(local.custom_domain_service_keys, key)
    ? "${local.custom_domain_prefix}${name}.${var.custom_domain_base}"
    : ""
  }

  order_service_domain_override = length(var.order_service_lb_managed_domains) > 0 ? {
    order_service = var.order_service_lb_managed_domains[0]
  } : {}

  raw_custom_service_domains = merge(
    local.default_service_domains,
    var.custom_service_domain_overrides,
    local.order_service_domain_override
  )
  custom_service_domains = local.skip_onboarding_domain_mapping ? merge(local.raw_custom_service_domains, {
    onboarding_service = ""
  }) : local.raw_custom_service_domains

  service_urls = {
    for key, name in local.service_names :
    key => local.custom_service_domains[key] != ""
    ? "https://${local.custom_service_domains[key]}"
    : "https://${name}-${local.project_number}.${var.region}.run.app"
  }

  domain_mappings = {
    for key, domain in local.custom_service_domains :
    key => domain
    if domain != "" && contains(local.custom_domain_service_keys, key)
  }

  dns_domain = var.cloud_dns_domain != "" ? var.cloud_dns_domain : var.custom_domain_base
  dns_extra_records = local.skip_onboarding_domain_mapping ? [] : (
    local.custom_service_domains.onboarding_service != ""
    ? [
      {
        name    = local.custom_service_domains.onboarding_service
        type    = "CNAME"
        ttl     = 300
        rrdatas = ["ghs.googlehosted.com."]
      }
    ]
    : []
  )
  expected_record_types = {
    for key, domain in local.domain_mappings :
    domain => (domain == local.dns_domain ? ["A", "AAAA"] : ["CNAME"])
  }

  cloud_run_defaults = {
    admin_service = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 120
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        FIRESTORE_PROJECT_ID = var.project_id
        FIREBASE_PROJECT_ID  = var.project_id
        REQUIRE_AUTH         = "true"
        CORS_ORIGINS         = join(",", var.admin_service_cors_origins)
      }
      secret_env_overrides = {}
    }
    agent_customization = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 120
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT             = var.environment_name
        FIRESTORE_PROJECT_ID    = var.project_id
        CORS_ORIGINS            = join(",", var.agent_customization_cors_origins)
        ELEVENLABS_API_BASE_URL = "https://api.elevenlabs.io"
      }
      secret_env_overrides = {}
    }
    order_service = {
      min_scale             = 0
      max_scale             = 20
      container_concurrency = 80
      timeout_seconds       = 300
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides         = {}
      secret_env_overrides  = {}
    }
    menu_ingestion = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 40
      timeout_seconds       = 300
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        MENU_BUCKET             = "${var.project_id}-menus-${var.environment_name}"
        MENU_INGEST_TOPIC       = "menu-ingest"
        MENU_UPDATES_TOPIC      = "menu-updates"
        MENU_MAX_PAGES          = "5"
        MENU_MAX_ITEMS_PER_PAGE = "40"
        MENU_MAX_TOTAL_ITEMS    = "120"
        VERTEX_PROJECT          = var.project_id
        VERTEX_LOCATION         = var.region
        VERTEX_MODEL            = "gemini-2.5-flash"
        # Gemini 3 image/text models for menu compositing & analysis.
        COMPOSITE_MODEL      = "gemini-3-pro-image-preview"
        ANALYSIS_MODEL       = "gemini-3-pro-preview"
        RENDER_MODEL         = "gemini-3-pro-image-preview"
        IMAGE_REGION         = "global"
        TEXT_REGION          = "global"
        GEN_TIMEOUT_MS       = "120000"
        PURE_GEMINI_IMAGE    = "true"
        GOOGLE_CLOUD_PROJECT = var.project_id
        USE_GENAI_IMAGE      = "true"
        AGENT_COMPOSITE_URL  = "https://genai-app-fastfoodmenuextraction-1-1764171394659-230152279015.us-central1.run.app"
        AGENT_ANALYSIS_URL   = "https://genai-app-countingcardsincomposite-1-176417409497-230152279015.us-central1.run.app"
        MENU_INGESTION_CORS_ORIGINS = join(",", [
          local.service_urls.admin_service,
          "http://localhost:3000",
          "http://localhost:4000",
          "http://localhost:8080",
        ])
        ALLOW_GOOGLE_ID_TOKENS    = "true"
        GOOGLE_ID_TOKEN_AUDIENCES = local.service_urls.menu_ingestion
        GOOGLE_ID_TOKEN_ALLOWED_EMAILS = join(",", [
          module.menu_ingestion_sa.email,
          module.agent_tools_sa.email,
          module.github_ci_sa.email,
        ])
      }
      secret_env_overrides = {}
    }
    notification_service = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 120
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT         = var.environment_name
        FIREBASE_PROJECT_ID = var.project_id
        # FIREBASE_SERVICE_ACCOUNT can be injected via overrides or Secret Manager if needed.
      }
      secret_env_overrides = {}
    }
    onboarding_service = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 120
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        GCS_BUCKET     = "${var.project_id}-menus-${var.environment_name}"
        CORS_ORIGINS   = join(",", var.onboarding_cors_origins)
        MAKE_PUBLIC    = "true"
        MENU_MAX_PAGES = "5"
      }
      secret_env_overrides = {}
    }
    payments_service = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 120
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT         = var.environment_name
        FIREBASE_PROJECT_ID = var.project_id
        CORS_ORIGINS = join(",", [
          "http://localhost:3000",
          "http://localhost:4000",
          "http://localhost:5173",
          "http://localhost:8080",
          "https://liive-dev-admin.web.app",
          "https://liive-dev-business.web.app",
          "https://liive-dev-consumer.web.app",
          "https://liive-dev-driver.web.app",
          "https://telegram-mini-oi2.web.app",
          local.service_urls.channel_gateway,
        ])
      }
      secret_env_overrides = {}
    }
    agent_webhooks = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 30
      cpu                   = "1000m"
      memory                = "256Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        FIRESTORE_PROJECT_ID = var.project_id
      }
      secret_env_overrides = {}
    }
    channel_gateway = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 45
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT                  = var.environment_name
        FIRESTORE_PROJECT_ID         = var.project_id
        ELEVENLABS_API_BASE_URL      = "https://api.elevenlabs.io"
        SESSION_IDLE_MINUTES         = "20"
        CUSTOMER_PROFILE_SERVICE_URL = local.service_urls.customer_profile
        RECOMMENDATION_SERVICE_URL   = local.service_urls.recommendation
        WAIT_TIME_SERVICE_URL        = local.service_urls.wait_time_service
      }
      secret_env_overrides = {}
    }
    channel_comms = {
      min_scale             = 0
      max_scale             = 5
      container_concurrency = 40
      timeout_seconds       = 30
      cpu                   = "1000m"
      memory                = "256Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT = var.environment_name
      }
      secret_env_overrides = {}
    }
    customer_profile = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 30
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        FIRESTORE_PROJECT_ID = var.project_id
      }
      secret_env_overrides = {}
    }
    recommendation = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 30
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        FIRESTORE_PROJECT_ID = var.project_id
      }
      secret_env_overrides = {}
    }
    agent_tools = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 60
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        JWT_ISSUER           = "ordering-intelligence"
        JWT_AUDIENCE         = "agent-tools"
        TOKEN_TTL_SECONDS    = "900"
        FIRESTORE_PROJECT_ID = var.project_id
        VERTEX_LOCATION      = var.region
        GEMINI_MODEL         = var.agent_tools_gemini_model
      }
      secret_env_overrides = {}
    }
    wait_time_service = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 60
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT            = var.environment_name
        FIRESTORE_PROJECT_ID   = var.project_id
        MIN_SAMPLES_FOR_MEDIAN = "10"
        MAX_SAMPLES_HISTORY    = "50"
      }
      secret_env_overrides = {}
    }
    dispatch_service = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 60
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT            = var.environment_name
        FIRESTORE_PROJECT_ID   = var.project_id
        REQUIRE_AUTH           = "true"
        INTERNAL_AUTH_AUDIENCE = local.service_urls.dispatch_service
        INTERNAL_ALLOWED_EMAILS = join(",", [
          module.agent_tools_sa.email,
          module.channel_gateway_sa.email,
          module.github_ci_sa.email,
        ])
        ORDER_SERVICE_URL                      = local.service_urls.order_service
        DISPATCH_EVENTS_TOPIC                  = module.core.pubsub_topics["dispatch-events"]
        ASSIGNMENT_TTL_SECONDS                 = "30"
        TOP_K_CANDIDATES                       = "5"
        DISPATCH_SERVICE_URL                   = local.service_urls.dispatch_service
        CLOUD_TASKS_PROJECT_ID                 = var.project_id
        CLOUD_TASKS_LOCATION                   = var.region
        CLOUD_TASKS_ASSIGNMENT_QUEUE           = "dispatch-assignments-${var.environment_name}"
        CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL = module.dispatch_tasks_sa.email
        CLOUD_TASKS_OIDC_AUDIENCE              = local.service_urls.dispatch_service
      }
      secret_env_overrides = {}
    }
    delivery_service = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 60
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT            = var.environment_name
        FIRESTORE_PROJECT_ID   = var.project_id
        REQUIRE_AUTH           = "true"
        INTERNAL_AUTH_AUDIENCE = local.service_urls.delivery_service
        INTERNAL_ALLOWED_EMAILS = join(",", [
          module.agent_tools_sa.email,
          module.github_ci_sa.email,
        ])
        ORDER_SERVICE_URL           = local.service_urls.order_service
        DISPATCH_SERVICE_URL        = local.service_urls.dispatch_service
        ORDERS_EVENTS_OIDC_AUDIENCE = local.service_urls.delivery_service
        DELIVERIES_EVENTS_TOPIC     = module.core.pubsub_topics["deliveries-events"]
        PROVIDER_MODE               = "mock"
      }
      secret_env_overrides = {}
    }
    typesense_indexer = {
      min_scale             = 0
      max_scale             = 10
      container_concurrency = 80
      timeout_seconds       = 900
      cpu                   = "1"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides = {
        ENVIRONMENT          = var.environment_name
        FIRESTORE_PROJECT_ID = var.project_id
        TYPESENSE_HOST       = var.typesense_host
        TYPESENSE_COLLECTION = "stores"
      }
      secret_env_overrides = {
        TYPESENSE_ADMIN_API_KEY = google_secret_manager_secret.typesense_admin_api_key.secret_id
      }
    }
  }

  cloud_run_defaults_normalized = {
    for key, defaults in local.cloud_run_defaults :
    key => merge(
      defaults,
      {
        image                = lookup(defaults, "image", null)
        env_overrides        = tomap(lookup(defaults, "env_overrides", {}))
        secret_env_overrides = tomap(lookup(defaults, "secret_env_overrides", {}))
      }
    )
  }

  cloud_run_overrides_normalized = {
    for key, overrides in var.cloud_run_overrides :
    key => {
      for k, v in merge(
        overrides,
        {
          env_overrides        = tomap(lookup(overrides, "env_overrides", {}))
          secret_env_overrides = tomap(lookup(overrides, "secret_env_overrides", {}))
        }
      ) : k => v if v != null
    }
  }

  cloud_run_config = {
    for key, defaults in local.cloud_run_defaults_normalized :
    key => (
      contains(keys(local.cloud_run_overrides_normalized), key)
      ? merge(defaults, local.cloud_run_overrides_normalized[key])
      : defaults
    )
  }
}

module "agent_tools_voice_cache" {
  count  = var.enable_agent_tools_redis_cache ? 1 : 0
  source = "../../modules/memorystore_redis"

  project_id        = var.project_id
  region            = var.region
  name              = "${var.environment_name}-agent-tools-voice-cache"
  network_self_link = module.core.network_self_link
  memory_size_gb    = var.agent_tools_redis_memory_gb
}

module "order_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "order-service-${var.environment_name}"
  display_name = "Order Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "admin_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "admin-service-${var.environment_name}"
  display_name = "Admin Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "agent_customization_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "agent-customization-${var.environment_name}"
  display_name = "Agent Customization (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "menu_ingestion_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "menu-ingestion-${var.environment_name}"
  display_name = "Menu Ingestion (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/pubsub.publisher",
    "roles/aiplatform.user",
    "roles/datastore.user"
  ]
}

module "notification_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "notification-service-${var.environment_name}"
  display_name = "Notification Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/pubsub.publisher",
    "roles/secretmanager.secretAccessor",
    "roles/cloudtasks.enqueuer",
    "roles/firebasecloudmessaging.admin"
  ]
}

module "onboarding_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "onboarding-service-${var.environment_name}"
  display_name = "Onboarding Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/storage.objectAdmin",
    "roles/datastore.user",
    "roles/datastore.owner",
    "roles/iam.serviceAccountTokenCreator"
  ]
}

module "payments_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "payments-service-${var.environment_name}"
  display_name = "Payments Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/secretmanager.secretAccessor"
  ]
}

module "agent_webhooks_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "agent-webhooks-${var.environment_name}"
  display_name = "Agent Webhooks (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "channel_gateway_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "channel-gateway-${var.environment_name}"
  display_name = "Channel Gateway (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "channel_comms_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "channel-comms-${var.environment_name}"
  display_name = "Channel Comms (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ]
}

module "typesense_indexer_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "typesense-indexer-${var.environment_name}"
  display_name = "Typesense Indexer (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/eventarc.eventReceiver"
  ]
}

module "agent_tools_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "agent-tools-${var.environment_name}"
  display_name = "Agent Tools (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/aiplatform.user"
  ]
}

module "customer_profile_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "customer-profile-${var.environment_name}"
  display_name = "Customer Profile (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "recommendation_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "recommendation-${var.environment_name}"
  display_name = "Recommendation Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "wait_time_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "wait-time-service-${var.environment_name}"
  display_name = "Wait Time Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "dispatch_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "dispatch-service-${var.environment_name}"
  display_name = "Dispatch Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/cloudtasks.enqueuer"
  ]
}

module "delivery_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "delivery-service-${var.environment_name}"
  display_name = "Delivery Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/pubsub.publisher"
  ]
}

module "orders_events_push_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "orders-events-push-${var.environment_name}"
  display_name  = "Orders Events Push (${var.environment_name})"
  project_roles = []
}

resource "google_secret_manager_secret" "genai_api_key" {
  project   = var.project_id
  secret_id = "genai-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_binding" "menu_ingestion_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.genai_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.menu_ingestion_sa.email}"]
}

# Onboarding service secrets (values to be set manually)
resource "google_secret_manager_secret" "stripe_secret_key" {
  project   = var.project_id
  secret_id = "stripe-secret-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stripe_webhook_secret" {
  project   = var.project_id
  secret_id = "stripe-webhook-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stripe_payments_webhook_secret" {
  project   = var.project_id
  secret_id = "stripe-payments-webhook-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stripe_publishable_key" {
  project   = var.project_id
  secret_id = "stripe-publishable-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "twilio_account_sid" {
  project   = var.project_id
  secret_id = "twilio-account-sid"

  replication {
    auto {}
  }
}

# Google Maps API key for geocoding/timezone
resource "google_secret_manager_secret" "google_maps_api_key" {
  project   = var.project_id
  secret_id = "google-maps-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "radar_api_key" {
  project   = var.project_id
  secret_id = "radar-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "uber_direct_api_key" {
  project   = var.project_id
  secret_id = "uber-direct-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "uber_direct_client_id" {
  project   = var.project_id
  secret_id = "uber-direct-client-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "uber_direct_client_secret" {
  project   = var.project_id
  secret_id = "uber-direct-client-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "uber_direct_customer_id" {
  project   = var.project_id
  secret_id = "uber-direct-customer-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "uber_direct_access_token" {
  project   = var.project_id
  secret_id = "uber-direct-access-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stuart_api_key" {
  project   = var.project_id
  secret_id = "stuart-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stuart_client_id" {
  project   = var.project_id
  secret_id = "stuart-client-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stuart_client_secret" {
  project   = var.project_id
  secret_id = "stuart-client-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "stuart_access_token" {
  project   = var.project_id
  secret_id = "stuart-access-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "elevenlabs_api_key" {
  project   = var.project_id
  secret_id = "elevenlabs-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "elevenlabs_conversation_init_secret" {
  project   = var.project_id
  secret_id = "elevenlabs-conversation-init-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "typesense_admin_api_key" {
  project   = var.project_id
  secret_id = "typesense-admin-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "typesense_search_api_key" {
  project   = var.project_id
  secret_id = "typesense-search-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "telegram_bot_token" {
  project   = var.project_id
  secret_id = "telegram-bot-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "telegram_webhook_secret" {
  project   = var.project_id
  secret_id = "telegram-webhook-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "discord_client_secret" {
  project   = var.project_id
  secret_id = "discord-client-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "discord_bot_token" {
  project   = var.project_id
  secret_id = "discord-bot-token"

  replication {
    auto {}
  }
}

# Agent tools OAuth/JWT secrets (values to be set manually)
resource "google_secret_manager_secret" "agent_tools_oauth_client_id" {
  project   = var.project_id
  secret_id = "agent-tools-oauth-client-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "agent_tools_oauth_client_secret" {
  project   = var.project_id
  secret_id = "agent-tools-oauth-client-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "agent_tools_jwt_signing_secret" {
  project   = var.project_id
  secret_id = "agent-tools-jwt-signing-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "onboarding_secret_access" {
  for_each = {
    stripe_secret_key      = google_secret_manager_secret.stripe_secret_key.secret_id
    stripe_webhook_secret  = google_secret_manager_secret.stripe_webhook_secret.secret_id
    stripe_publishable_key = google_secret_manager_secret.stripe_publishable_key.secret_id
    twilio_account_sid     = google_secret_manager_secret.twilio_account_sid.secret_id
    google_maps_api_key    = google_secret_manager_secret.google_maps_api_key.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.onboarding_service_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "payments_service_secret_access" {
  for_each = {
    stripe_secret_key     = google_secret_manager_secret.stripe_secret_key.secret_id
    stripe_webhook_secret = google_secret_manager_secret.stripe_payments_webhook_secret.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.payments_service_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "payments_webhook_secret_github_ci_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.stripe_payments_webhook_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.github_ci_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "agent_customization_elevenlabs_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.elevenlabs_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.agent_customization_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "onboarding_elevenlabs_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.elevenlabs_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.onboarding_service_sa.email}"
}

resource "google_secret_manager_secret_iam_binding" "agent_webhooks_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.elevenlabs_conversation_init_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.agent_webhooks_sa.email}"]
}

resource "google_secret_manager_secret_iam_binding" "typesense_indexer_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.typesense_admin_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.typesense_indexer_sa.email}"]
}

resource "google_secret_manager_secret_iam_binding" "channel_gateway_secret_access" {
  for_each = {
    telegram_webhook_secret  = google_secret_manager_secret.telegram_webhook_secret.secret_id
    discord_client_secret    = google_secret_manager_secret.discord_client_secret.secret_id
    typesense_search_api_key = google_secret_manager_secret.typesense_search_api_key.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.channel_gateway_sa.email}"]
}

resource "google_secret_manager_secret_iam_member" "channel_gateway_elevenlabs_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.elevenlabs_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.channel_gateway_sa.email}"
}

resource "google_secret_manager_secret_iam_binding" "telegram_bot_token_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.telegram_bot_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${module.channel_gateway_sa.email}",
    "serviceAccount:${module.channel_comms_sa.email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "discord_bot_token_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.discord_bot_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${module.channel_gateway_sa.email}",
    "serviceAccount:${module.channel_comms_sa.email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "agent_tools_secret_access" {
  for_each = {
    oauth_client_id     = google_secret_manager_secret.agent_tools_oauth_client_id.secret_id
    oauth_client_secret = google_secret_manager_secret.agent_tools_oauth_client_secret.secret_id
    jwt_signing_secret  = google_secret_manager_secret.agent_tools_jwt_signing_secret.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.agent_tools_sa.email}"]
}

resource "google_secret_manager_secret_iam_binding" "dispatch_service_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.radar_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.dispatch_service_sa.email}"]
}

resource "google_secret_manager_secret_iam_binding" "delivery_service_secret_access" {
  for_each = {
    uber_direct_api_key       = google_secret_manager_secret.uber_direct_api_key.secret_id
    uber_direct_client_id     = google_secret_manager_secret.uber_direct_client_id.secret_id
    uber_direct_client_secret = google_secret_manager_secret.uber_direct_client_secret.secret_id
    uber_direct_customer_id   = google_secret_manager_secret.uber_direct_customer_id.secret_id
    uber_direct_access_token  = google_secret_manager_secret.uber_direct_access_token.secret_id
    stuart_api_key            = google_secret_manager_secret.stuart_api_key.secret_id
    stuart_client_id          = google_secret_manager_secret.stuart_client_id.secret_id
    stuart_client_secret      = google_secret_manager_secret.stuart_client_secret.secret_id
    stuart_access_token       = google_secret_manager_secret.stuart_access_token.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  members   = ["serviceAccount:${module.delivery_service_sa.email}"]
}

resource "google_pubsub_topic_iam_member" "order_pubsub_publisher" {
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.order_service_sa.email}"
}

resource "google_pubsub_topic_iam_member" "dispatch_pubsub_publisher" {
  project = var.project_id
  topic   = module.core.pubsub_topics["dispatch-events"]
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.dispatch_service_sa.email}"
}

resource "google_pubsub_topic_iam_member" "deliveries_pubsub_publisher" {
  project = var.project_id
  topic   = module.core.pubsub_topics["deliveries-events"]
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.delivery_service_sa.email}"
}

resource "google_pubsub_topic_iam_member" "onboarding_menu_ingest_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.menu_ingest.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.onboarding_service_sa.email}"
}

resource "google_pubsub_topic" "menu_ingest" {
  name    = "menu-ingest"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_pubsub_topic" "menu_ingest_dlq" {
  name    = "menu-ingest-dlq"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_project_iam_member" "cloudservices_serviceusage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${tostring(data.google_project.current.number)}@cloudservices.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudservices_projectiam" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${tostring(data.google_project.current.number)}@cloudservices.gserviceaccount.com"
}

# Eventarc service agent permissions for triggers used by Typesense indexer.
resource "google_project_iam_member" "eventarc_service_agent" {
  project = var.project_id
  role    = "roles/eventarc.serviceAgent"
  member  = "serviceAccount:service-${local.project_number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "menu_ingestion" {
  name     = "${var.project_id}-menus-${var.environment_name}"
  location = var.region
  project  = var.project_id

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "menu_ingestion_sa_access" {
  bucket = google_storage_bucket.menu_ingestion.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.menu_ingestion_sa.email}"
}

resource "google_storage_bucket_iam_member" "onboarding_sa_access" {
  bucket = google_storage_bucket.menu_ingestion.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.onboarding_service_sa.email}"
}

# Allow the service account to sign URLs (needed for upload signed URLs)
resource "google_service_account_iam_member" "menu_ingestion_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.menu_ingestion_sa.email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${module.menu_ingestion_sa.email}"
}

resource "google_project_iam_audit_config" "all_services" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Allow Pub/Sub to mint OIDC tokens as the push service account.
resource "google_service_account_iam_member" "orders_events_pubsub_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.orders_events_push_sa.email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${local.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "orders_events_to_customer_profile" {
  name    = "orders-events-to-customer-profile-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.customer_profile}/tasks/orders-events"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.customer_profile
    }
  }

  depends_on = [
    module.customer_profile,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_subscription" "orders_events_to_recommendation" {
  name    = "orders-events-to-recommendation-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.recommendation}/tasks/orders-events"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.recommendation
    }
  }

  depends_on = [
    module.recommendation,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_subscription" "orders_events_to_channel_comms" {
  name    = "orders-events-to-channel-comms-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.channel_comms}/events/orders"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.channel_comms
    }
  }

  depends_on = [
    module.channel_comms,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_subscription" "orders_events_to_wait_time_service" {
  name    = "orders-events-to-wait-time-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.wait_time_service}/tasks/orders-events"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.wait_time_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.wait_time_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_subscription" "orders_events_to_dispatch_service" {
  name    = "orders-events-to-dispatch-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.dispatch_service}/tasks/orders-events"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.dispatch_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.dispatch_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_subscription" "orders_events_to_delivery_service" {
  name    = "orders-events-to-delivery-${var.environment_name}"
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]

  push_config {
    push_endpoint = "${local.service_urls.delivery_service}/tasks/orders-events"

    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.delivery_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.delivery_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

module "order_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.order_service
  image                 = coalesce(local.cloud_run_config.order_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/order-service:latest")
  min_scale             = local.cloud_run_config.order_service.min_scale
  max_scale             = local.cloud_run_config.order_service.max_scale
  container_concurrency = local.cloud_run_config.order_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.order_service.timeout_seconds
  cpu                   = local.cloud_run_config.order_service.cpu
  memory                = local.cloud_run_config.order_service.memory
  startup_cpu_boost     = local.cloud_run_config.order_service.startup_cpu_boost
  service_account       = module.order_service_sa.email

  env_vars = merge({
    ENVIRONMENT                   = var.environment_name
    FIRESTORE_PROJECT_ID          = var.project_id
    PUBSUB_TOPIC_ORDERS           = "orders-events"
    ORDERS_EVENTS_PAYLOAD_VERSION = "v2"
    # Allow agent-tools to authenticate using Cloud Run IAM-style ID tokens.
    INTERNAL_AUTH_AUDIENCE = local.service_urls.order_service
    INTERNAL_ALLOWED_EMAILS = join(",", [
      module.agent_tools_sa.email,
      module.payments_service_sa.email,
      module.dispatch_service_sa.email,
      module.delivery_service_sa.email,
      module.channel_gateway_sa.email,
      module.github_ci_sa.email,
    ])
    # CORS: Allow Flutter web dev server and other localhost ports
    CORS_ORIGINS = "http://localhost:3000,http://localhost:4000,http://localhost:4001,http://localhost:8080,http://localhost:65269,http://127.0.0.1:4000"
  }, lookup(local.cloud_run_config.order_service, "env_overrides", {}))

  depends_on = [
    module.core,
    module.order_service_sa,
    google_pubsub_topic_iam_member.order_pubsub_publisher
  ]
}

module "menu_ingestion" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.menu_ingestion
  image                 = coalesce(local.cloud_run_config.menu_ingestion.image, "${local.image_registry_host}/${local.image_registry_project}/services/menu-ingestion:latest")
  min_scale             = local.cloud_run_config.menu_ingestion.min_scale
  max_scale             = local.cloud_run_config.menu_ingestion.max_scale
  container_concurrency = local.cloud_run_config.menu_ingestion.container_concurrency
  timeout_seconds       = local.cloud_run_config.menu_ingestion.timeout_seconds
  cpu                   = local.cloud_run_config.menu_ingestion.cpu
  memory                = local.cloud_run_config.menu_ingestion.memory
  startup_cpu_boost     = local.cloud_run_config.menu_ingestion.startup_cpu_boost
  service_account       = module.menu_ingestion_sa.email
  env_vars = merge({
    ENVIRONMENT = var.environment_name
  }, lookup(local.cloud_run_config.menu_ingestion, "env_overrides", {}))
  secret_env_vars = lookup(local.cloud_run_config.menu_ingestion, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.menu_ingestion_sa,
    google_storage_bucket.menu_ingestion,
    google_pubsub_topic.menu_ingest
  ]
}

module "notification_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.notification_service
  image                 = coalesce(local.cloud_run_config.notification_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/notification-service:latest")
  min_scale             = local.cloud_run_config.notification_service.min_scale
  max_scale             = local.cloud_run_config.notification_service.max_scale
  container_concurrency = local.cloud_run_config.notification_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.notification_service.timeout_seconds
  cpu                   = local.cloud_run_config.notification_service.cpu
  memory                = local.cloud_run_config.notification_service.memory
  startup_cpu_boost     = local.cloud_run_config.notification_service.startup_cpu_boost
  service_account       = module.notification_service_sa.email
  env_vars = merge({
    ENVIRONMENT                     = var.environment_name
    FIREBASE_PROJECT_ID             = var.project_id
    CUSTOMER_PROFILE_SERVICE_URL    = local.service_urls.customer_profile
    ORDERS_EVENTS_OIDC_AUDIENCE     = local.service_urls.notification_service
    DISPATCH_EVENTS_OIDC_AUDIENCE   = local.service_urls.notification_service
    DELIVERIES_EVENTS_OIDC_AUDIENCE = local.service_urls.notification_service

    NOTIFICATION_SERVICE_URL               = local.service_urls.notification_service
    CLOUD_TASKS_PROJECT_ID                 = var.project_id
    CLOUD_TASKS_LOCATION                   = var.region
    CLOUD_TASKS_READY_ESCALATION_QUEUE     = "ready-escalation-${var.environment_name}"
    CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL = module.notification_tasks_sa.email
    CLOUD_TASKS_OIDC_AUDIENCE              = local.service_urls.notification_service
    ELEVENLABS_API_BASE_URL                = "https://api.elevenlabs.io"
    NOTIFICATIONS_DRY_RUN                  = "true"
  }, lookup(local.cloud_run_config.notification_service, "env_overrides", {}))
  secret_env_vars = merge({
    TWILIO_ACCOUNT_SID = google_secret_manager_secret.twilio_account_sid.secret_id,
    TWILIO_AUTH_TOKEN  = "twilio-auth-token",
    ELEVENLABS_API_KEY = google_secret_manager_secret.elevenlabs_api_key.secret_id
  }, lookup(local.cloud_run_config.notification_service, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.notification_service_sa
  ]
}

module "payments_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.payments_service
  image                 = coalesce(local.cloud_run_config.payments_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/payments-service:latest")
  min_scale             = local.cloud_run_config.payments_service.min_scale
  max_scale             = local.cloud_run_config.payments_service.max_scale
  container_concurrency = local.cloud_run_config.payments_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.payments_service.timeout_seconds
  cpu                   = local.cloud_run_config.payments_service.cpu
  memory                = local.cloud_run_config.payments_service.memory
  startup_cpu_boost     = local.cloud_run_config.payments_service.startup_cpu_boost
  service_account       = module.payments_service_sa.email
  env_vars = merge({
    ENVIRONMENT              = var.environment_name
    FIREBASE_PROJECT_ID      = var.project_id
    ORDER_SERVICE_URL        = local.service_urls.order_service
    NOTIFICATION_SERVICE_URL = local.service_urls.notification_service
    INTERNAL_AUTH_AUDIENCE   = local.service_urls.payments_service
    INTERNAL_ALLOWED_EMAILS = join(",", [
      module.agent_tools_sa.email,
      module.github_ci_sa.email,
    ])
    STRIPE_WEBHOOK_ALLOWED_EVENTS = "checkout.session.completed,checkout.session.expired,payment_intent.succeeded,payment_intent.payment_failed,setup_intent.succeeded"
  }, lookup(local.cloud_run_config.payments_service, "env_overrides", {}))
  secret_env_vars = merge({
    STRIPE_SECRET_KEY     = google_secret_manager_secret.stripe_secret_key.secret_id,
    STRIPE_WEBHOOK_SECRET = google_secret_manager_secret.stripe_payments_webhook_secret.secret_id
  }, lookup(local.cloud_run_config.payments_service, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.payments_service_sa,
    google_secret_manager_secret_iam_member.payments_service_secret_access
  ]
}

module "onboarding_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.onboarding_service
  image                 = coalesce(local.cloud_run_config.onboarding_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/onboarding-service:latest")
  min_scale             = local.cloud_run_config.onboarding_service.min_scale
  max_scale             = local.cloud_run_config.onboarding_service.max_scale
  container_concurrency = local.cloud_run_config.onboarding_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.onboarding_service.timeout_seconds
  cpu                   = local.cloud_run_config.onboarding_service.cpu
  memory                = local.cloud_run_config.onboarding_service.memory
  startup_cpu_boost     = local.cloud_run_config.onboarding_service.startup_cpu_boost
  service_account       = module.onboarding_service_sa.email
  env_vars = merge({
    ENVIRONMENT = var.environment_name
    # ElevenLabs template agents to duplicate for tenant-specific agents.
    ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID  = "agent_7201kbfs3pbpe1tsv4dmakk1207q"
    ELEVENLABS_TEMPLATE_AUTO_PARTS_AGENT_ID = "agent_9201kbnjy570f0ysjk9mssmwewm3"
  }, lookup(local.cloud_run_config.onboarding_service, "env_overrides", {}))
  secret_env_vars = merge({
    STRIPE_SECRET_KEY      = google_secret_manager_secret.stripe_secret_key.secret_id,
    STRIPE_WEBHOOK_SECRET  = google_secret_manager_secret.stripe_webhook_secret.secret_id,
    STRIPE_PUBLISHABLE_KEY = google_secret_manager_secret.stripe_publishable_key.secret_id,
    TWILIO_ACCOUNT_SID     = google_secret_manager_secret.twilio_account_sid.secret_id,
    TWILIO_AUTH_TOKEN      = "twilio-auth-token",
    GOOGLE_MAPS_API_KEY    = google_secret_manager_secret.google_maps_api_key.secret_id,
    ELEVENLABS_API_KEY     = google_secret_manager_secret.elevenlabs_api_key.secret_id,
  }, lookup(local.cloud_run_config.onboarding_service, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.onboarding_service_sa,
    google_storage_bucket.menu_ingestion
  ]
}

module "agent_webhooks" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.agent_webhooks
  image                 = coalesce(local.cloud_run_config.agent_webhooks.image, "${local.image_registry_host}/${local.image_registry_project}/services/agent-webhooks:latest")
  min_scale             = local.cloud_run_config.agent_webhooks.min_scale
  max_scale             = local.cloud_run_config.agent_webhooks.max_scale
  container_concurrency = local.cloud_run_config.agent_webhooks.container_concurrency
  timeout_seconds       = local.cloud_run_config.agent_webhooks.timeout_seconds
  cpu                   = local.cloud_run_config.agent_webhooks.cpu
  memory                = local.cloud_run_config.agent_webhooks.memory
  startup_cpu_boost     = local.cloud_run_config.agent_webhooks.startup_cpu_boost
  service_account       = module.agent_webhooks_sa.email
  # Restrict direct public ingress so Cloud Armor can be enforced via the HTTPS load balancer.
  ingress = "internal-and-cloud-load-balancing"

  env_vars = merge({
    CUSTOMER_PROFILE_SERVICE_URL     = local.service_urls.customer_profile
    RECOMMENDATION_SERVICE_URL       = local.service_urls.recommendation
    WAIT_TIME_SERVICE_URL            = local.service_urls.wait_time_service
    CUSTOMER_PERSONALIZATION_VERSION = "v1"
    INTERNAL_AUTH_AUDIENCE           = local.service_urls.agent_webhooks
    INTERNAL_ALLOWED_EMAILS = join(",", [
      module.agent_tools_sa.email,
      module.github_ci_sa.email,
    ])
  }, lookup(local.cloud_run_config.agent_webhooks, "env_overrides", {}))
  secret_env_vars = merge({
    ELEVENLABS_CONVERSATION_INIT_SECRET = google_secret_manager_secret.elevenlabs_conversation_init_secret.secret_id
  }, lookup(local.cloud_run_config.agent_webhooks, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.agent_webhooks_sa,
    google_secret_manager_secret_iam_binding.agent_webhooks_secret_access
  ]
}

module "channel_gateway" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.channel_gateway
  image                 = coalesce(local.cloud_run_config.channel_gateway.image, "${local.image_registry_host}/${local.image_registry_project}/services/channel-gateway:latest")
  min_scale             = local.cloud_run_config.channel_gateway.min_scale
  max_scale             = local.cloud_run_config.channel_gateway.max_scale
  container_concurrency = local.cloud_run_config.channel_gateway.container_concurrency
  timeout_seconds       = local.cloud_run_config.channel_gateway.timeout_seconds
  cpu                   = local.cloud_run_config.channel_gateway.cpu
  memory                = local.cloud_run_config.channel_gateway.memory
  startup_cpu_boost     = local.cloud_run_config.channel_gateway.startup_cpu_boost
  service_account       = module.channel_gateway_sa.email

  env_vars = merge({
    ENVIRONMENT                  = var.environment_name
    FIRESTORE_PROJECT_ID         = var.project_id
    ELEVENLABS_API_BASE_URL      = "https://api.elevenlabs.io"
    CUSTOMER_PROFILE_SERVICE_URL = local.service_urls.customer_profile
    RECOMMENDATION_SERVICE_URL   = local.service_urls.recommendation
    WAIT_TIME_SERVICE_URL        = local.service_urls.wait_time_service
    ORDER_SERVICE_URL            = local.service_urls.order_service
    PAYMENTS_SERVICE_URL         = local.service_urls.payments_service
    DISPATCH_SERVICE_URL         = local.service_urls.dispatch_service
    TELEGRAM_WEBAPP_URL          = "https://telegram-mini-oi2.web.app"
    DISCORD_CLIENT_ID            = "1457874399339347988"
    DISCORD_PUBLIC_KEY           = "96b99f7ce4c32905ea11af7e3bcd9507d5a02d5459f851e8cb0f7b116c800149"
    DISCORD_ACTIVITY_CHANNEL_ID  = "1458247508806471863"
    SNAPCHAT_CLIENT_ID           = "7277929e-9bf0-4943-be4d-2bf11b8cbe66"
    TYPESENSE_HOST               = var.typesense_host
    TYPESENSE_COLLECTION         = "stores"
    CORS_ORIGINS                 = join(",", concat(var.channel_gateway_cors_origins, [local.service_urls.channel_gateway]))
    INTERNAL_AUTH_AUDIENCE       = local.service_urls.channel_gateway
    INTERNAL_ALLOWED_EMAILS = join(",", [
      module.agent_tools_sa.email,
      module.github_ci_sa.email,
    ])
  }, lookup(local.cloud_run_config.channel_gateway, "env_overrides", {}))
  secret_env_vars = merge({
    ELEVENLABS_API_KEY       = google_secret_manager_secret.elevenlabs_api_key.secret_id
    TELEGRAM_BOT_TOKEN       = google_secret_manager_secret.telegram_bot_token.secret_id
    TELEGRAM_WEBHOOK_SECRET  = google_secret_manager_secret.telegram_webhook_secret.secret_id
    DISCORD_CLIENT_SECRET    = google_secret_manager_secret.discord_client_secret.secret_id
    DISCORD_BOT_TOKEN        = google_secret_manager_secret.discord_bot_token.secret_id
    TYPESENSE_SEARCH_API_KEY = google_secret_manager_secret.typesense_search_api_key.secret_id
  }, lookup(local.cloud_run_config.channel_gateway, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.channel_gateway_sa,
    google_secret_manager_secret_iam_binding.channel_gateway_secret_access,
    google_secret_manager_secret_iam_binding.discord_bot_token_access
  ]
}

module "channel_comms" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.channel_comms
  image                 = coalesce(local.cloud_run_config.channel_comms.image, "${local.image_registry_host}/${local.image_registry_project}/services/channel-comms:latest")
  min_scale             = local.cloud_run_config.channel_comms.min_scale
  max_scale             = local.cloud_run_config.channel_comms.max_scale
  container_concurrency = local.cloud_run_config.channel_comms.container_concurrency
  timeout_seconds       = local.cloud_run_config.channel_comms.timeout_seconds
  cpu                   = local.cloud_run_config.channel_comms.cpu
  memory                = local.cloud_run_config.channel_comms.memory
  startup_cpu_boost     = local.cloud_run_config.channel_comms.startup_cpu_boost
  service_account       = module.channel_comms_sa.email

  env_vars = merge({
    ENVIRONMENT = var.environment_name
  }, lookup(local.cloud_run_config.channel_comms, "env_overrides", {}))
  secret_env_vars = merge({
    TELEGRAM_BOT_TOKEN = google_secret_manager_secret.telegram_bot_token.secret_id
    DISCORD_BOT_TOKEN  = google_secret_manager_secret.discord_bot_token.secret_id
  }, lookup(local.cloud_run_config.channel_comms, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.channel_comms_sa,
    google_secret_manager_secret_iam_binding.telegram_bot_token_access,
    google_secret_manager_secret_iam_binding.discord_bot_token_access
  ]
}

module "customer_profile" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.customer_profile
  image                 = coalesce(local.cloud_run_config.customer_profile.image, "${local.image_registry_host}/${local.image_registry_project}/services/customer-profile-service:latest")
  min_scale             = local.cloud_run_config.customer_profile.min_scale
  max_scale             = local.cloud_run_config.customer_profile.max_scale
  container_concurrency = local.cloud_run_config.customer_profile.container_concurrency
  timeout_seconds       = local.cloud_run_config.customer_profile.timeout_seconds
  cpu                   = local.cloud_run_config.customer_profile.cpu
  memory                = local.cloud_run_config.customer_profile.memory
  startup_cpu_boost     = local.cloud_run_config.customer_profile.startup_cpu_boost
  service_account       = module.customer_profile_sa.email

  env_vars        = lookup(local.cloud_run_config.customer_profile, "env_overrides", {})
  secret_env_vars = lookup(local.cloud_run_config.customer_profile, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.customer_profile_sa
  ]
}

module "recommendation" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.recommendation
  image                 = coalesce(local.cloud_run_config.recommendation.image, "${local.image_registry_host}/${local.image_registry_project}/services/recommendation-service:latest")
  min_scale             = local.cloud_run_config.recommendation.min_scale
  max_scale             = local.cloud_run_config.recommendation.max_scale
  container_concurrency = local.cloud_run_config.recommendation.container_concurrency
  timeout_seconds       = local.cloud_run_config.recommendation.timeout_seconds
  cpu                   = local.cloud_run_config.recommendation.cpu
  memory                = local.cloud_run_config.recommendation.memory
  startup_cpu_boost     = local.cloud_run_config.recommendation.startup_cpu_boost
  service_account       = module.recommendation_sa.email

  env_vars        = lookup(local.cloud_run_config.recommendation, "env_overrides", {})
  secret_env_vars = lookup(local.cloud_run_config.recommendation, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.recommendation_sa
  ]
}

module "wait_time_service" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.wait_time_service
  image                 = coalesce(local.cloud_run_config.wait_time_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/wait-time-service:latest")
  min_scale             = local.cloud_run_config.wait_time_service.min_scale
  max_scale             = local.cloud_run_config.wait_time_service.max_scale
  container_concurrency = local.cloud_run_config.wait_time_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.wait_time_service.timeout_seconds
  cpu                   = local.cloud_run_config.wait_time_service.cpu
  memory                = local.cloud_run_config.wait_time_service.memory
  startup_cpu_boost     = local.cloud_run_config.wait_time_service.startup_cpu_boost
  service_account       = module.wait_time_service_sa.email

  env_vars        = lookup(local.cloud_run_config.wait_time_service, "env_overrides", {})
  secret_env_vars = lookup(local.cloud_run_config.wait_time_service, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.wait_time_service_sa
  ]
}

module "typesense_indexer" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.typesense_indexer
  image                 = coalesce(local.cloud_run_config.typesense_indexer.image, "${local.image_registry_host}/${local.image_registry_project}/services/typesense-indexer:latest")
  min_scale             = local.cloud_run_config.typesense_indexer.min_scale
  max_scale             = local.cloud_run_config.typesense_indexer.max_scale
  container_concurrency = local.cloud_run_config.typesense_indexer.container_concurrency
  timeout_seconds       = local.cloud_run_config.typesense_indexer.timeout_seconds
  cpu                   = local.cloud_run_config.typesense_indexer.cpu
  memory                = local.cloud_run_config.typesense_indexer.memory
  startup_cpu_boost     = local.cloud_run_config.typesense_indexer.startup_cpu_boost
  service_account       = module.typesense_indexer_sa.email

  env_vars        = lookup(local.cloud_run_config.typesense_indexer, "env_overrides", {})
  secret_env_vars = lookup(local.cloud_run_config.typesense_indexer, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.typesense_indexer_sa,
    google_secret_manager_secret_iam_binding.typesense_indexer_secret_access
  ]
}

module "dispatch_service" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.dispatch_service
  image                 = coalesce(local.cloud_run_config.dispatch_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/dispatch-service:latest")
  min_scale             = local.cloud_run_config.dispatch_service.min_scale
  max_scale             = local.cloud_run_config.dispatch_service.max_scale
  container_concurrency = local.cloud_run_config.dispatch_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.dispatch_service.timeout_seconds
  cpu                   = local.cloud_run_config.dispatch_service.cpu
  memory                = local.cloud_run_config.dispatch_service.memory
  startup_cpu_boost     = local.cloud_run_config.dispatch_service.startup_cpu_boost
  service_account       = module.dispatch_service_sa.email

  env_vars = lookup(local.cloud_run_config.dispatch_service, "env_overrides", {})
  secret_env_vars = merge({
    RADAR_API_KEY = google_secret_manager_secret.radar_api_key.secret_id
  }, lookup(local.cloud_run_config.dispatch_service, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.dispatch_service_sa,
    google_secret_manager_secret_iam_binding.dispatch_service_secret_access
  ]
}

module "delivery_service" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.delivery_service
  image                 = coalesce(local.cloud_run_config.delivery_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/delivery-service:latest")
  min_scale             = local.cloud_run_config.delivery_service.min_scale
  max_scale             = local.cloud_run_config.delivery_service.max_scale
  container_concurrency = local.cloud_run_config.delivery_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.delivery_service.timeout_seconds
  cpu                   = local.cloud_run_config.delivery_service.cpu
  memory                = local.cloud_run_config.delivery_service.memory
  startup_cpu_boost     = local.cloud_run_config.delivery_service.startup_cpu_boost
  service_account       = module.delivery_service_sa.email

  env_vars = lookup(local.cloud_run_config.delivery_service, "env_overrides", {})
  secret_env_vars = merge({
    UBER_DIRECT_API_KEY       = google_secret_manager_secret.uber_direct_api_key.secret_id
    UBER_DIRECT_CLIENT_ID     = google_secret_manager_secret.uber_direct_client_id.secret_id
    UBER_DIRECT_CLIENT_SECRET = google_secret_manager_secret.uber_direct_client_secret.secret_id
    UBER_DIRECT_CUSTOMER_ID   = google_secret_manager_secret.uber_direct_customer_id.secret_id
    UBER_DIRECT_ACCESS_TOKEN  = google_secret_manager_secret.uber_direct_access_token.secret_id
    STUART_API_KEY            = google_secret_manager_secret.stuart_api_key.secret_id
    STUART_CLIENT_ID          = google_secret_manager_secret.stuart_client_id.secret_id
    STUART_CLIENT_SECRET      = google_secret_manager_secret.stuart_client_secret.secret_id
    STUART_ACCESS_TOKEN       = google_secret_manager_secret.stuart_access_token.secret_id
  }, lookup(local.cloud_run_config.delivery_service, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.delivery_service_sa,
    google_secret_manager_secret_iam_binding.delivery_service_secret_access
  ]
}

module "agent_tools" {
  source                = "../../modules/cloud_run_service_v2"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.agent_tools
  image                 = coalesce(local.cloud_run_config.agent_tools.image, "${local.image_registry_host}/${local.image_registry_project}/services/agent-tools:latest")
  min_scale             = local.cloud_run_config.agent_tools.min_scale
  max_scale             = local.cloud_run_config.agent_tools.max_scale
  container_concurrency = local.cloud_run_config.agent_tools.container_concurrency
  timeout_seconds       = local.cloud_run_config.agent_tools.timeout_seconds
  cpu                   = local.cloud_run_config.agent_tools.cpu
  memory                = local.cloud_run_config.agent_tools.memory
  startup_cpu_boost     = local.cloud_run_config.agent_tools.startup_cpu_boost
  service_account       = module.agent_tools_sa.email
  # IMPORTANT: restrict direct public ingress so Cloud Armor can be enforced via the HTTPS load balancer.
  ingress = "internal-and-cloud-load-balancing"

  env_vars = merge({
    ENVIRONMENT           = var.environment_name
    ORDER_SERVICE_URL     = local.service_urls.order_service
    WAIT_TIME_SERVICE_URL = local.service_urls.wait_time_service
    DISPATCH_SERVICE_URL  = local.service_urls.dispatch_service
    DELIVERY_SERVICE_URL  = local.service_urls.delivery_service
    PAYMENTS_SERVICE_URL  = local.service_urls.payments_service
    FIRESTORE_PROJECT_ID  = var.project_id
    VERTEX_LOCATION       = var.region
    GEMINI_MODEL          = var.agent_tools_gemini_model
    }, var.enable_agent_tools_redis_cache ? {
    REDIS_ADDR = "${module.agent_tools_voice_cache[0].host}:${module.agent_tools_voice_cache[0].port}"
  } : {}, lookup(local.cloud_run_config.agent_tools, "env_overrides", {}))

  secret_env_vars = merge({
    OAUTH_CLIENT_ID     = google_secret_manager_secret.agent_tools_oauth_client_id.secret_id
    OAUTH_CLIENT_SECRET = google_secret_manager_secret.agent_tools_oauth_client_secret.secret_id
    JWT_SIGNING_SECRET  = google_secret_manager_secret.agent_tools_jwt_signing_secret.secret_id
  }, lookup(local.cloud_run_config.agent_tools, "secret_env_overrides", {}))
  direct_vpc_network    = var.enable_agent_tools_redis_cache ? module.core.network_id : null
  direct_vpc_subnetwork = var.enable_agent_tools_redis_cache ? module.core.subnetwork_id : null
  direct_vpc_egress     = var.enable_agent_tools_redis_cache ? "PRIVATE_RANGES_ONLY" : "PRIVATE_RANGES_ONLY"

  depends_on = [
    module.core,
    module.agent_tools_sa,
    google_secret_manager_secret_iam_binding.agent_tools_secret_access
  ]
}

module "admin_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.admin_service
  image                 = coalesce(local.cloud_run_config.admin_service.image, "${local.image_registry_host}/${local.image_registry_project}/services/admin-service:latest")
  min_scale             = local.cloud_run_config.admin_service.min_scale
  max_scale             = local.cloud_run_config.admin_service.max_scale
  container_concurrency = local.cloud_run_config.admin_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.admin_service.timeout_seconds
  cpu                   = local.cloud_run_config.admin_service.cpu
  memory                = local.cloud_run_config.admin_service.memory
  startup_cpu_boost     = local.cloud_run_config.admin_service.startup_cpu_boost
  service_account       = module.admin_service_sa.email

  env_vars        = merge({}, lookup(local.cloud_run_config.admin_service, "env_overrides", {}))
  secret_env_vars = lookup(local.cloud_run_config.admin_service, "secret_env_overrides", {})

  depends_on = [
    module.core,
    module.admin_service_sa
  ]
}

module "agent_customization_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.agent_customization
  image                 = coalesce(local.cloud_run_config.agent_customization.image, "${local.image_registry_host}/${local.image_registry_project}/services/agent-customization-service:latest")
  min_scale             = local.cloud_run_config.agent_customization.min_scale
  max_scale             = local.cloud_run_config.agent_customization.max_scale
  container_concurrency = local.cloud_run_config.agent_customization.container_concurrency
  timeout_seconds       = local.cloud_run_config.agent_customization.timeout_seconds
  cpu                   = local.cloud_run_config.agent_customization.cpu
  memory                = local.cloud_run_config.agent_customization.memory
  startup_cpu_boost     = local.cloud_run_config.agent_customization.startup_cpu_boost
  service_account       = module.agent_customization_sa.email

  env_vars = merge({
    ENVIRONMENT             = var.environment_name
    FIRESTORE_PROJECT_ID    = var.project_id
    ELEVENLABS_API_BASE_URL = "https://api.elevenlabs.io"
    CORS_ORIGINS            = join(",", var.agent_customization_cors_origins)
  }, lookup(local.cloud_run_config.agent_customization, "env_overrides", {}))
  secret_env_vars = merge({
    ELEVENLABS_API_KEY = google_secret_manager_secret.elevenlabs_api_key.secret_id
  }, lookup(local.cloud_run_config.agent_customization, "secret_env_overrides", {}))

  depends_on = [
    module.core,
    module.agent_customization_sa,
    google_secret_manager_secret_iam_member.agent_customization_elevenlabs_access
  ]
}

resource "google_cloud_run_service_iam_member" "admin_service_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.admin_service
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.admin_service]
}

resource "google_cloud_run_service_iam_member" "agent_customization_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.agent_customization
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.agent_customization_service]
}

resource "google_cloud_run_service_iam_member" "onboarding_service_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.onboarding_service
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.onboarding_service]
}

resource "google_cloud_run_service_iam_member" "agent_webhooks_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.agent_webhooks
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.agent_webhooks]
}

resource "google_cloud_run_service_iam_member" "channel_gateway_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.channel_gateway
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.channel_gateway]
}

module "agent_webhooks_waf" {
  source      = "../../modules/cloud_armor_policy"
  project_id  = var.project_id
  enabled     = var.enable_cloud_armor
  policy_name = "${var.environment_name}-agent-webhooks-waf"
  description = "Baseline Cloud Armor policy for dev agent-webhooks (ElevenLabs IP allowlist)."

  blocked_ip_ranges = []
  # NOTE: When allowlist is enabled, Cloud Armor will default-deny all other IPs.
  # Keep this list in sync with ElevenLabs docs.
  allowed_ip_ranges = var.enable_elevenlabs_ip_allowlist ? [
    "34.67.146.145/32",
    "34.59.11.47/32",
    "35.204.38.71/32",
    "34.147.113.54/32",
    "35.185.187.110/32",
    "35.247.157.189/32",
    "34.77.234.246/32",
    "34.140.184.144/32",
    "34.93.26.174/32",
    "34.93.252.69/32",
  ] : []
  enable_rate_limit           = true
  rate_limit_threshold        = 600
  rate_limit_interval_seconds = 60
}

resource "google_cloud_run_service_iam_member" "agent_webhooks_lb_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.agent_webhooks
  role     = "roles/run.invoker"
  # Required for Serverless NEG / HTTPS LB to invoke Cloud Run.
  member = "serviceAccount:service-${local.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.agent_webhooks]
}

module "agent_webhooks_lb" {
  source             = "../../modules/serverless_https_lb"
  project_id         = var.project_id
  region             = var.region
  cloud_run_service  = local.service_names.agent_webhooks
  environment_name   = var.environment_name
  hostname           = "${var.environment_name}-agent-webhooks"
  security_policy_id = module.agent_webhooks_waf.policy_id
  certificate_mode   = "MANAGED"
  managed_domains    = []
}

module "agent_tools_waf" {
  source      = "../../modules/cloud_armor_policy"
  project_id  = var.project_id
  enabled     = var.enable_cloud_armor
  policy_name = "${var.environment_name}-agent-tools-waf"
  description = "Baseline Cloud Armor policy for dev agent-tools."

  blocked_ip_ranges = []
  # ElevenLabs static egress IPs (from their docs). Keep this list in sync with ElevenLabs.
  # NOTE: enabling this allowlist will block access from other IPs (including your laptop).
  allowed_ip_ranges = var.enable_elevenlabs_ip_allowlist ? [
    "34.67.146.145/32",
    "34.59.11.47/32",
    "35.204.38.71/32",
    "34.147.113.54/32",
    "35.185.187.110/32",
    "35.247.157.189/32",
    "34.77.234.246/32",
    "34.140.184.144/32",
    "34.93.26.174/32",
    "34.93.252.69/32",
  ] : []
  enable_rate_limit           = true
  rate_limit_threshold        = 600
  rate_limit_interval_seconds = 60
}

resource "google_cloud_run_v2_service_iam_member" "agent_tools_lb_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.agent_tools
  role     = "roles/run.invoker"
  # Required for Serverless NEG / HTTPS LB to invoke Cloud Run.
  member = "serviceAccount:service-${local.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.agent_tools]
}

# Cloud Run behind a serverless HTTPS LB typically uses ingress restrictions for isolation.
# Allow unauthenticated invocation so the LB can forward requests without end-user identity.
resource "google_cloud_run_v2_service_iam_member" "agent_tools_public" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.agent_tools
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.agent_tools]
}

resource "google_cloud_run_v2_service_iam_member" "customer_profile_agent_webhooks_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.customer_profile
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_webhooks_sa.email}"

  depends_on = [module.customer_profile]
}

resource "google_cloud_run_v2_service_iam_member" "customer_profile_channel_gateway_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.customer_profile
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.channel_gateway_sa.email}"

  depends_on = [module.customer_profile, module.channel_gateway_sa]
}

resource "google_cloud_run_v2_service_iam_member" "customer_profile_orders_events_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.customer_profile
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.customer_profile]
}

resource "google_cloud_run_v2_service_iam_member" "customer_profile_notification_service_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.customer_profile
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.notification_service_sa.email}"

  depends_on = [module.customer_profile, module.notification_service_sa]
}

resource "google_cloud_run_v2_service_iam_member" "recommendation_agent_webhooks_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.recommendation
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_webhooks_sa.email}"

  depends_on = [module.recommendation]
}

resource "google_cloud_run_v2_service_iam_member" "recommendation_channel_gateway_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.recommendation
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.channel_gateway_sa.email}"

  depends_on = [module.recommendation, module.channel_gateway_sa]
}

resource "google_cloud_run_v2_service_iam_member" "recommendation_orders_events_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.recommendation
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.recommendation]
}

resource "google_cloud_run_v2_service_iam_member" "wait_time_service_agent_webhooks_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.wait_time_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_webhooks_sa.email}"

  depends_on = [module.wait_time_service]
}

resource "google_cloud_run_v2_service_iam_member" "wait_time_service_channel_gateway_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.wait_time_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.channel_gateway_sa.email}"

  depends_on = [module.wait_time_service, module.channel_gateway_sa]
}

resource "google_cloud_run_v2_service_iam_member" "wait_time_service_agent_tools_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.wait_time_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_tools_sa.email}"

  depends_on = [module.wait_time_service, module.agent_tools_sa]
}

resource "google_cloud_run_v2_service_iam_member" "wait_time_service_orders_events_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.wait_time_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.wait_time_service]
}

resource "google_cloud_run_v2_service_iam_member" "typesense_indexer_eventarc_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.typesense_indexer
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.typesense_indexer_sa.email}"

  depends_on = [module.typesense_indexer]
}

resource "google_cloud_run_v2_service_iam_member" "dispatch_service_public" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.dispatch_service
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.dispatch_service]
}

resource "google_cloud_run_v2_service_iam_member" "dispatch_service_agent_tools_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.dispatch_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_tools_sa.email}"

  depends_on = [module.dispatch_service, module.agent_tools_sa]
}

resource "google_cloud_run_v2_service_iam_member" "dispatch_service_orders_events_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.dispatch_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.dispatch_service]
}

resource "google_cloud_run_v2_service_iam_member" "delivery_service_agent_tools_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.delivery_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_tools_sa.email}"

  depends_on = [module.delivery_service, module.agent_tools_sa]
}

resource "google_cloud_run_v2_service_iam_member" "delivery_service_orders_events_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = local.service_names.delivery_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.delivery_service]
}

module "agent_tools_lb" {
  source            = "../../modules/serverless_https_lb"
  project_id        = var.project_id
  region            = var.region
  cloud_run_service = local.service_names.agent_tools
  environment_name  = var.environment_name
  # Only used for self-signed cert CN; managed cert uses nip.io by default.
  hostname           = "${var.environment_name}-agent-tools"
  security_policy_id = module.agent_tools_waf.policy_id
  certificate_mode   = "MANAGED"
  managed_domains    = []
}

resource "google_cloud_run_service_iam_member" "order_service_agent_tools_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.order_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.agent_tools_sa.email}"

  depends_on = [module.order_service, module.agent_tools_sa]
}

resource "google_cloud_run_service_iam_member" "order_service_channel_gateway_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.order_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.channel_gateway_sa.email}"

  depends_on = [module.order_service, module.channel_gateway_sa]
}

resource "google_cloud_run_service_iam_member" "payments_service_channel_gateway_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.payments_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.channel_gateway_sa.email}"

  depends_on = [module.payments_service, module.channel_gateway_sa]
}

resource "google_cloud_run_service_iam_member" "payments_service_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.payments_service
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.payments_service]
}

resource "google_cloud_run_service_iam_member" "channel_comms_orders_events_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.channel_comms
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.orders_events_push_sa.email}"

  depends_on = [module.channel_comms, module.orders_events_push_sa]
}

# Allow browser/mobile clients to reach the notification API; auth is enforced inside the service.
resource "google_cloud_run_service_iam_member" "notification_service_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.notification_service
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.notification_service]
}

resource "google_cloud_run_service_iam_member" "menu_ingestion_public" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.menu_ingestion
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.menu_ingestion]
}

resource "google_eventarc_trigger" "typesense_indexer_stores" {
  name                    = "typesense-indexer-stores-${var.environment_name}"
  location                = var.firestore_location
  event_data_content_type = "application/protobuf"

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.firestore.document.v1.written"
  }

  matching_criteria {
    attribute = "database"
    value     = "(default)"
  }

  matching_criteria {
    attribute = "document"
    value     = "stores/{storeId}"
  }

  destination {
    cloud_run_service {
      service = module.typesense_indexer.name
      region  = var.region
    }
  }

  service_account = module.typesense_indexer_sa.email

  depends_on = [
    module.typesense_indexer,
    module.typesense_indexer_sa
  ]
}

resource "google_eventarc_trigger" "typesense_indexer_tenants" {
  name                    = "typesense-indexer-tenants-${var.environment_name}"
  location                = var.firestore_location
  event_data_content_type = "application/protobuf"

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.firestore.document.v1.written"
  }

  matching_criteria {
    attribute = "database"
    value     = "(default)"
  }

  matching_criteria {
    attribute = "document"
    value     = "tenants/{tenantId}"
  }

  destination {
    cloud_run_service {
      service = module.typesense_indexer.name
      region  = var.region
    }
  }

  service_account = module.typesense_indexer_sa.email

  depends_on = [
    module.typesense_indexer,
    module.typesense_indexer_sa
  ]
}

resource "google_pubsub_subscription" "menu_ingest_push" {
  name    = "menu-ingest-push"
  topic   = google_pubsub_topic.menu_ingest.name
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.menu_ingestion}/tasks/process"
    oidc_token {
      service_account_email = module.menu_ingestion_sa.email
      audience              = local.service_urls.menu_ingestion
    }
  }

  ack_deadline_seconds = 30

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.menu_ingest_dlq.id
    max_delivery_attempts = 5
  }
}

# Push menu-updates completion events to onboarding service
resource "google_pubsub_subscription" "menu_updates_to_onboarding" {
  name    = "menu-updates-to-onboarding"
  topic   = google_pubsub_topic.menu_updates.name
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.onboarding_service}/ingest-pubsub"
    oidc_token {
      service_account_email = module.onboarding_service_sa.email
    }
  }

  ack_deadline_seconds = 20
}
