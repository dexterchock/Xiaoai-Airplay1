IMAGE_NAME ?= xiaoai-airplay1-toolchain:dev
export IMAGE_NAME

.PHONY: build build-shairport package clean

build:
	docker build -t $(IMAGE_NAME) $(CURDIR)

build-shairport:
	bash $(CURDIR)/build-shairport.sh

package: build-shairport
	bash $(CURDIR)/package-release.sh

clean:
	rm -rf $(CURDIR)/../build $(CURDIR)/../dist
