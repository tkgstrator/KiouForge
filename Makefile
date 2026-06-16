# ===========================================================================
# KiouForge — IPA-Patch tweak Makefile.
#
# Targets:
#   make            — JB rootless .deb (MSHookFunction via libsubstrate)
#   make package    — same, packaged
#   make jailed     — Dobby-static .dylib for Sideloadly injection (iOS 13+)
#   make binpatch   — Dobby-static .dylib for the statically-patched IPA path
#                     (iOS 18 sideload; the only mode that survives CSM).
#   make ipa        — patched IPA assembled from $(DECRYPTED_IPA)
# ===========================================================================

# ---------------------------------------------------------------------------
# PROJECT VARIABLES
# ---------------------------------------------------------------------------
TWEAK_NAME               := KiouForge
TWEAK_SOURCES_DIR        := Sources/$(TWEAK_NAME)

TARGET_PROCESS           := KIOU
TARGET_BUNDLE_ID         := com.neconome.shogi

DECRYPTED_IPA            ?= $(CURDIR)/assets/Kiou-1.0.1.ipa
IPA_RECIPE               := recipes.kiouforge
IPA_FRAMEWORK            := UnityFramework

BUILD_COMMIT_DEFINE      := KIOU_FORGE_COMMIT

# ---------------------------------------------------------------------------
# Theos boilerplate.
# ---------------------------------------------------------------------------
TARGET                   := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES := $(TARGET_PROCESS)
ARCHS                    := arm64
THEOS_PACKAGE_SCHEME     := rootless
THEOS_DEVICE_IP          := 192.168.0.49

include $(THEOS)/makefiles/common.mk

$(TWEAK_NAME)_FILES      := $(shell find $(TWEAK_SOURCES_DIR) -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
$(TWEAK_NAME)_FILES      += Sources/Common/logging.m
$(TWEAK_NAME)_FILES      += Sources/Common/binpatch.m

BUILD_COMMIT             ?= $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)

_CONTROL_VERSION         := $(shell grep '^Version:' control | awk '{print $$2}')
# Theos sets DEBUG=1 by default; FINALPACKAGE=1 clears it for release builds.
ifneq ($(FINALPACKAGE),1)
KIOU_FORGE_VERSION       ?= $(_CONTROL_VERSION)-dbg
else
KIOU_FORGE_VERSION       ?= $(_CONTROL_VERSION)
endif

KIOU_FORGE_DEB_VERSION   := $(patsubst v%,%,$(KIOU_FORGE_VERSION))
KIOU_FORGE_DEB_VERSION   := $(shell echo "$(KIOU_FORGE_DEB_VERSION)" | sed -E 's/^([^0-9])/0.0.0+\1/')
THEOS_PACKAGE_BASE_VERSION := $(KIOU_FORGE_DEB_VERSION)

$(TWEAK_NAME)_CFLAGS     := -fobjc-arc -Wno-unused-function \
                            -D$(BUILD_COMMIT_DEFINE)=\"$(BUILD_COMMIT)\" \
                            -DKIOU_FORGE_VERSION=\"$(KIOU_FORGE_VERSION)\" \
                            -ISources/Common -I$(TWEAK_SOURCES_DIR)
$(TWEAK_NAME)_FRAMEWORKS := Foundation UIKit

ifeq ($(BINPATCH),1)
    JAILED                   := 1
    $(TWEAK_NAME)_CFLAGS     += -DIPA_BINPATCH=1 -DIPA_LOG_TO_DOCUMENTS=1
endif

ifeq ($(JAILED),1)
    $(TWEAK_NAME)_CFLAGS     += -DIPA_JAILED=1 -Ivendor/dobby/include
    $(TWEAK_NAME)_LDFLAGS    := -Lvendor/dobby/lib -ldobby -lc++ -lc++abi
else
    $(TWEAK_NAME)_LDFLAGS    := -lsubstrate
endif

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "chmod 755 /var/jb/Library/MobileSubstrate/DynamicLibraries/$(TWEAK_NAME).dylib"
	install.exec "sleep 1; (open $(TARGET_BUNDLE_ID) 2>/dev/null || uiopen $(TARGET_BUNDLE_ID):// 2>/dev/null || echo 'no launcher tool; start $(TARGET_PROCESS) manually')"

jailed::
	$(MAKE) JAILED=1 clean
	$(MAKE) JAILED=1 all
	$(ECHO_NOTHING)mkdir -p packages/jailed$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib packages/jailed/$(TWEAK_NAME).dylib$(ECHO_END)
	@echo "jailed dylib -> packages/jailed/$(TWEAK_NAME).dylib"
	@$(THEOS)/toolchain/linux/iphone/bin/otool -L packages/jailed/$(TWEAK_NAME).dylib 2>/dev/null \
	  || otool -L packages/jailed/$(TWEAK_NAME).dylib 2>/dev/null \
	  || echo "(otool unavailable)"

binpatch::
	$(MAKE) BINPATCH=1 clean
	$(MAKE) BINPATCH=1 all
	$(ECHO_NOTHING)mkdir -p packages/binpatch$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib packages/binpatch/$(TWEAK_NAME).dylib$(ECHO_END)
	@echo "binpatch dylib -> packages/binpatch/$(TWEAK_NAME).dylib"
	@$(THEOS)/toolchain/linux/iphone/bin/otool -L packages/binpatch/$(TWEAK_NAME).dylib 2>/dev/null \
	  || otool -L packages/binpatch/$(TWEAK_NAME).dylib 2>/dev/null \
	  || echo "(otool unavailable)"

IPA_DYLIB                := $(CURDIR)/packages/binpatch/$(TWEAK_NAME).dylib

ipa:: binpatch
	@echo "==> assembling patched IPA from $(DECRYPTED_IPA)"
	@if [ ! -f "$(DECRYPTED_IPA)" ]; then \
	  echo "error: decrypted IPA missing at $(DECRYPTED_IPA)"; \
	  exit 1; \
	fi
	@./shared/tools/build_patched_ipa.sh \
	  --recipe    "$(IPA_RECIPE)" \
	  --framework "$(IPA_FRAMEWORK)" \
	  --dylib     "$(IPA_DYLIB)" \
	  --input     "$(DECRYPTED_IPA)"

.PHONY: hooks
hooks::
	git config core.hooksPath scripts
	@echo "git hooks now resolve under scripts/"
