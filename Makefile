.PHONY: build run dev stop clean

CONFIGURATION ?= release

build:
	CONFIGURATION="$(CONFIGURATION)" ./scripts/build-app.sh

run: stop
	$(MAKE) build
	open --env LAYER_DESIGN_PREVIEW=1 .build/Layer.app

dev:
	./scripts/dev.sh

stop:
	@pkill -x Layer 2>/dev/null || true

clean:
	swift package clean
