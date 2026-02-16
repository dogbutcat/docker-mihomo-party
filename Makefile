VERSION := $(shell cat VERSION)
PLATFORM ?= linux/amd64
GOST_VERSION ?= 3.2.6
IMAGE_NAME := docker-clash-party
REMOTE_IMAGE := dogbutcat/mihomo-party
CONTAINER_NAME := test_clash_party

HTTP_PORT ?= 3000

build: stop
	docker buildx build --platform $(PLATFORM) \
		--build-arg VERSION=$(VERSION) \
		--build-arg GOST_VERSION=$(GOST_VERSION) \
		-t $(IMAGE_NAME) --load .

push:
	docker buildx build --platform linux/amd64 \
		--build-arg VERSION=$(VERSION) \
		--build-arg GOST_VERSION=$(GOST_VERSION) \
		-t $(REMOTE_IMAGE):$(VERSION)-amd64 --push .
	docker buildx build --platform linux/arm64 \
		--build-arg VERSION=$(VERSION) \
		--build-arg GOST_VERSION=$(GOST_VERSION) \
		-t $(REMOTE_IMAGE):$(VERSION)-arm64 --push .
	docker manifest create $(REMOTE_IMAGE):$(VERSION) \
		$(REMOTE_IMAGE):$(VERSION)-amd64 \
		$(REMOTE_IMAGE):$(VERSION)-arm64
	docker manifest push $(REMOTE_IMAGE):$(VERSION)
	docker manifest create $(REMOTE_IMAGE):latest \
		$(REMOTE_IMAGE):$(VERSION)-amd64 \
		$(REMOTE_IMAGE):$(VERSION)-arm64
	docker manifest push $(REMOTE_IMAGE):latest

stop:
	@if [ "$$(docker ps -a --format '{{.Names}}' | grep $(CONTAINER_NAME))" = "$(CONTAINER_NAME)" ]; then \
		docker stop $(CONTAINER_NAME); \
	fi

test: build
	docker run --rm \
		-d --name $(CONTAINER_NAME) \
		-e PUID=0 \
		-e PGID=0 \
		-e USER=root \
		-e TZ=Asia/Shanghai \
		-e CUSTOM_PORT=$(HTTP_PORT) \
		-p $(HTTP_PORT):$(HTTP_PORT) \
		--cap-add NET_ADMIN \
		--cap-add SYS_MODULE \
		--device /dev/net/tun:/dev/net/tun \
		--shm-size 1g \
		$(IMAGE_NAME)

run: test
	@echo "Container $(CONTAINER_NAME) started."
	@echo "Access KasmVNC at http://localhost:$(HTTP_PORT)"

logs:
	docker logs -f $(CONTAINER_NAME)

.PHONY: build push stop test run logs