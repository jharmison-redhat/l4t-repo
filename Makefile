RUNTIME := podman
CLIENT := oc
REGISTRY := registry.jharmison.com
REPOSITORY := l4t/repo
TAG := latest
IMAGE = $(REGISTRY)/$(REPOSITORY):$(TAG)

.PHONY: all
all: .push
	$(CLIENT) apply -k deploy

.build: repo.asc repobuild.sh nginx.conf Containerfile dist/SOURCES/jharmison-l4t.repo dist/SPECS/jharmison-l4t-repo.spec $(wildcard repo/*/*/*.rpm)
	@$(RUNTIME) build --pull=always --build-arg GPG_PRIVATE_KEY="$(shell cat repo.asc | base64 -w0)" . -t $(IMAGE)
	@touch .build

.push: .build
	@$(RUNTIME) push $(IMAGE)
	@touch .push
