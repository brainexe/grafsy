NAME = grafsy
# This is space separated words, e.g. 'git@github.com leoleovich grafsy.git' or 'https   github.com leoleovich grafsy.git'
REPO_LIST = $(shell git remote get-url origin | tr ':/' ' ' )
# And here we take the word before the last to get the organization name
ORG_NAME = $(word $(words $(REPO_LIST)), first_word $(REPO_LIST))
# version in format $(tag without leading v).c$(commits since release).g$(sha1)
VERSION = $(shell git describe --long --tags 2>/dev/null | sed 's/^v//;s/\([^-]*-g\)/c\1/;s/-/./g')
VENDOR = "GitHub Actions of $(ORG_NAME)/$(NAME) <null@null.null>"
URL = https://github.com/$(ORG_NAME)/$(NAME)
define DESC =
'A very light proxy for graphite metrics with additional features
 This software receives carbon metrics localy, buffering them, aggregating, filtering bad metrics, and periodicaly sends them to one or few carbon servers'
endef
GO_FILES = $(shell find -name '*.go')
PKG_FILES = build/$(NAME)_$(VERSION)_amd64.deb build/$(NAME)-$(VERSION)-1.x86_64.rpm
SUM_FILES = build/sha256sum build/md5sum
GO_FLAGS = -trimpath
GO_BUILD = go build $(GO_FLAGS) -ldflags "-X 'main.version=$(VERSION)'" -o $@ $<

export GO111MODULE=on

.PHONY: all clean docker test version

all: build

version:
	@echo $(VERSION)

clean:
	rm -rf artifact
	rm -rf build

rebuild: clean all

# Run tests
test:
	go vet ./...
	go test -v ./...

build: build/$(NAME) build/$(NAME)-client

docker:
	docker build --build-arg IMAGE=$(ORG_NAME)/$(NAME) -t $(ORG_NAME)/$(NAME):latest -f Dockerfile .

build/$(NAME): $(NAME)/main.go
	$(GO_BUILD)

build/$(NAME)-client: $(NAME)-client/main.go
	$(GO_BUILD)

build/$(NAME).exe: $(NAME)/main.go
	GOOS=windows $(GO_BUILD)

build/$(NAME)-client.exe: $(NAME)-client/main.go
	GOOS=windows $(GO_BUILD)

#########################################################
# Prepare artifact directory and set outputs for upload #
#########################################################
github_artifact: $(foreach art,$(PKG_FILES) $(SUM_FILES), artifact/$(notdir $(art)))

artifact:
	mkdir $@

# Link artifact to directory with setting step output to filename
artifact/%: ART=$(notdir $@)
artifact/%: TYPE=$(lastword $(subst ., ,$(ART)))
artifact/%: build/% | artifact
	cp -l $< $@
	@echo '::set-output name=$(TYPE)::$(ART)'

#######
# END #
#######

#############
# Packaging #
#############

# Prepare everything for packaging
.ONESHELL:
build/pkg: build/$(NAME)-client_linux_x64 build/$(NAME)_linux_x64 $(NAME).toml
	cd build
	mkdir -p pkg/etc/$(NAME)/example/
	mkdir -p pkg/usr/bin
	cp -l $(NAME)_linux_x64 pkg/usr/bin/$(NAME)
	cp -l $(NAME)-client_linux_x64 pkg/usr/bin/$(NAME)-client
	cp -l ../$(NAME).toml pkg/etc/$(NAME)/example/

build/$(NAME)_linux_x64: $(NAME)/main.go
	GOOS=linux GOARCH=amd64 $(GO_BUILD)

build/$(NAME)-client_linux_x64: $(NAME)-client/main.go
	GOOS=linux GOARCH=amd64 $(GO_BUILD)


# md5 and sha256 sum-files for packages
$(SUM_FILES): COMMAND = $(notdir $@)
$(SUM_FILES): PKG_FILES_NAME = $(notdir $(PKG_FILES))
.ONESHELL:
$(SUM_FILES): $(PKG_FILES)
	cd build
	$(COMMAND) $(PKG_FILES_NAME) > $(COMMAND)

packages: nfpm $(SUM_FILES)
deb: nfpm
rpm: nfpm
nfpm: build build/pkg
	$(MAKE) $(PKG_FILES) ARCH=amd64

.ONESHELL:
$(PKG_FILES): TYPE = $(subst .,,$(suffix $@))
$(PKG_FILES): nfpm.yaml
	NAME=$(NAME) VENDOR=$(VENDOR) DESCRIPTION=$(DESCRIPTION) ARCH=$(ARCH) VERSION_STRING=$(VERSION) nfpm package --packager $(TYPE) --target build/
#######
# END #
#######
