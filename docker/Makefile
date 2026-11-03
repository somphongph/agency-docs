# Agency Dashboard — docker helpers
#
#   make up           # build + start api + web (agency-stack/)
#   make down         # stop them (add ARGS=-v to drop volumes)
#   make logs         # follow stack logs
#   make infra        # start Grafana + Prometheus (agency-infra/)
#   make infra-down   # stop them
#   make build-versions  # build agency-{api,web}:{develop,sse} from git refs
#   make pull            # run the prebuilt "develop" images (agency-pull/)
#   make pull-down       # stop them
#
# Images are built from ../../agency-api and ../../agency-web.

STACK_COMPOSE = docker compose -f agency-stack/docker-compose.yml
INFRA_COMPOSE = docker compose -f agency-infra/docker-compose.yml
PULL_COMPOSE  = docker compose -f agency-pull/docker-compose.yml

.PHONY: up down ps logs infra infra-down infra-ps infra-logs build-versions pull pull-down pull-ps pull-logs

up:
	@$(STACK_COMPOSE) up -d --build
	@echo "Web        http://localhost:4200"
	@echo "API        http://localhost:8080/api/v1/health"

down:
	@$(STACK_COMPOSE) down $(ARGS)

ps:
	@$(STACK_COMPOSE) ps

logs:
	@$(STACK_COMPOSE) logs -f --tail=100

infra:
	@$(INFRA_COMPOSE) up -d
	@echo "Grafana    http://localhost:3000  (user admin, password: GRAFANA_ADMIN_PASSWORD or admin)"
	@echo "Prometheus http://localhost:9090"

infra-down:
	@$(INFRA_COMPOSE) down $(ARGS)

infra-ps:
	@$(INFRA_COMPOSE) ps

infra-logs:
	@$(INFRA_COMPOSE) logs -f --tail=100

build-versions:
	@./scripts/build-versions.sh

pull:
	@$(PULL_COMPOSE) up -d --force-recreate
	@echo "Web        http://localhost:4201"
	@echo "API        http://localhost:8081/api/v1/dashboard"

pull-down:
	@$(PULL_COMPOSE) down $(ARGS)

pull-ps:
	@$(PULL_COMPOSE) ps

pull-logs:
	@$(PULL_COMPOSE) logs -f --tail=100
