# CUR_PATH := $(shell pwd)
VERSION := $(shell cat VERSION)
TARGETARCH ?= amd64
IMAGE_NAME := docker-clash-party
CONTAINER_NAME := test_clash_party

build: stop
# 	docker buildx build --platform linux/amd64 --build-arg VERSION=$(VERSION) --build-arg TARGETARCH=$(TARGETARCH) -t $(IMAGE_NAME) .
	docker build --rm \
		--build-arg VERSION=$(VERSION) \
		--build-arg TARGETARCH=$(TARGETARCH) \
		-t $(IMAGE_NAME) .

stop:
	@if [ "$$(docker ps -a --format '{{.Names}}' | grep $(CONTAINER_NAME))" = "$(CONTAINER_NAME)" ]; then \
		docker stop $(CONTAINER_NAME); \
	fi

test: build
	docker run --rm \
		-d --name $(CONTAINER_NAME) \
		-e PUID=1000 \
		-e PGID=1000 \
		-e TZ=Asia/Shanghai \
		-p 3000:3000 \
		-p 6901:6901 \
		-p 7890:7890 \
		$(IMAGE_NAME)

run: test
	@echo "Container $(CONTAINER_NAME) started."
	@echo "Access KasmVNC at http://localhost:3000"

logs:
	docker logs -f $(CONTAINER_NAME)

.PHONY: build stop test run logs