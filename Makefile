# vim:ts=4:sts=4:sw=4:noet

CFLAGS=-O3
LDFLAGS=

COPT=--cc-opt=$(CFLAGS) --control=127.0.0.1:8443 --ld-opt=$(LDFLAGS)
COPT+=--modules=build --state=build --tmp=build --tests

JHW_CLASS = jhw/WEB-INF/classes/app.class

HW_LIST = hw/hw_c hw/hw_go hw/$(JHW_CLASS) hw/venv hw/venv/.uvloop
NODE_MODULE = hw/node_modules/unit-http/build/Release/unit-http.node
LIBUNIT = unit/build/libunit.a

JETTY_VER=9.4.35.v20201120
JETTY_NAME=jetty-distribution
JETTY_TAR=$(JETTY_NAME)-$(JETTY_VER).tar.gz
JETTY_URL=https://repo1.maven.org/maven2/org/eclipse/jetty/$(JETTY_NAME)/$(JETTY_VER)/$(JETTY_TAR)

WAIT_3_DONE = ( for i in 0 1 2; do sleep 1 && echo -n . ; done ) && echo " done"

ifeq ($(shell uname -s),Darwin)
   ULIMIT_FILES := true
else
   ULIMIT_FILES := ulimit -S -n 65536
endif

.PHONY: all clean

all: unit/build/unitd $(HW_LIST) $(NODE_MODULE)

unit:
	@echo "Fetching Unit source from repo ..."
	hg clone http://hg.nginx.org/unit

unit/.patched: | unit
	@echo "Applying patches ..."
	cd unit && \
	for p in ../patches/*.patch; do patch -p1 -i $$p; done && \
	touch .patched

clean: stop
	@echo "Cleaning all staff ..."
	rm -rf unit hw/node_modules/unit-http $(HW_LIST) \
		hw/__pycache__ hw/package-lock.json \
		hw/$(JETTY_NAME)-$(JETTY_VER) hw/$(JETTY_TAR) hw/jhw-base

unit/build/.configure: unit/.patched
	@echo "Configuring Unit and modules ..."
	cd unit && \
	./configure ${COPT} && \
	./configure python --config=python3.8-config && \
	./configure go --go-path= && \
	./configure php && \
	./configure perl && \
	./configure ruby && \
	./configure java && \
	./configure nodejs
	touch $@

.NOTPARALLEL: unit/build/unitd $(LIBUNIT)

unit/build/unitd $(LIBUNIT) &: unit/build/.configure
	@echo "Compiling Unit and modules ..."
	$(MAKE) -C unit all build/libunit.a

unit/ctags: | unit
	cd unit && ctags -R src go

.PHONY: start start-all start-unit start-uvicorn start-jetty start-go
start: start-unit
start-all: start-unit start-uvicorn start-jetty start-go

start-unit: unit/unit.pid hw-static

unit/unit.pid: SHELL:=/bin/bash
unit/unit.pid: | unit/build/unitd $(HW_LIST) $(NODE_MODULE)
	@echo "Starting Unit ..."
	@cd unit && \
	$(ULIMIT_FILES) && \
	( [ -f unit.log ] && mv unit.log unit-`date +'%Y%m%d-%H%M%S'`.log ||: ) && \
	build/unitd
	@$(WAIT_3_DONE)
	@curl -X PUT -d @unit.conf http://127.0.0.1:8443/config
	@ps aux | grep unit | grep -v grep


.PHONY: hw-static
hw-static: $(addprefix hw/static/,index.html 1k 4k 16k 64k 1m)

hw/static:
	mkdir -p $@

hw/static/index.html: | hw/static unit/unit.pid
	curl -o $@ http://127.0.0.1:8405/

hw/static/%: | hw/static unit/unit.pid
	curl -o $@ http://127.0.0.1:8405/$*


start-uvicorn: hw/uvicorn.pid

hw/uvicorn.pid: SHELL:=/bin/bash
hw/uvicorn.pid: | hw/venv/.uvicorn hw/venv/.uvloop
	@echo -n "Starting uvicorn "
	@cd hw && source venv/bin/activate && \
	$(ULIMIT_FILES) && \
	( uvicorn --host 0.0.0.0 --port 8300 --loop uvloop --log-level warning --no-access-log --no-use-colors --workers 16 hw-asgi:application & )
	@$(WAIT_3_DONE)
	@ps aux | grep 'spawn_main\|bin/uvicorn' | grep -v grep | awk '{ print $$2 }' > $@


start-jetty: hw/jhw-base/jetty.pid

hw/jhw-base/jetty.pid: SHELL:=/bin/bash
hw/jhw-base/jetty.pid: | hw/$(JETTY_NAME)-$(JETTY_VER) hw/jhw-base hw/jhw-base/webapps/$(JHW_CLASS)
	@echo "Starting Jetty ..."
	@cd hw/jhw-base && \
	$(ULIMIT_FILES) && \
	( java -Dorg.eclipse.jetty.LEVEL=WARN -jar ../$(JETTY_NAME)-$(JETTY_VER)/start.jar & echo $$! > jetty.pid ) && \
	$(WAIT_3_DONE)


start-go: hw/hw_go.pid

hw/hw_go.pid: SHELL:=/bin/bash
hw/hw_go.pid: | hw/hw_go
	@echo "Starting Go ..."
	@$(ULIMIT_FILES) && \
	( ./hw/hw_go & echo $$! > $@ ) && \
	$(WAIT_3_DONE)


.PHONY: stop stop-unit stop-uvicorn stop-jetty stop-go
.IGNORE: stop stop-unit stop-uvicorn stop-jetty stop-go
stop: stop-unit stop-uvicorn stop-jetty stop-go

stop-unit: SHELL:=/bin/bash
stop-unit:
	@if [ -f unit/unit.pid ]; then \
	    echo -n "Stopping Unit " && \
	    kill `cat unit/unit.pid` && \
	    $(WAIT_3_DONE) && \
	    ( ps aux | grep unit | grep -v grep ||: ); \
	fi

stop-uvicorn: SHELL:=/bin/bash
stop-uvicorn:
	@if [ -f hw/uvicorn.pid ]; then \
	    echo -n "Stopping uvicorn " && \
	    kill `cat hw/uvicorn.pid` && \
	    $(WAIT_3_DONE) && \
	    rm -f hw/uvicorn.pid; \
	fi

stop-jetty: SHELL:=/bin/bash
stop-jetty:
	@if [ -f hw/jhw-base/jetty.pid ]; then \
	    echo -n "Stopping jetty " && \
	    kill `cat hw/jhw-base/jetty.pid` && \
	    $(WAIT_3_DONE) && \
	    rm -f hw/jhw-base/jetty.pid; \
	fi

stop-go: SHELL:=/bin/bash
stop-go:
	@if [ -f hw/hw_go.pid ]; then \
	    echo -n "Stopping Go " && \
	    kill `cat hw/hw_go.pid` && \
	    $(WAIT_3_DONE) && \
	    rm -f hw/hw_go.pid; \
	fi


$(NODE_MODULE): unit/build/.configure $(LIBUNIT)
	@echo "Installing Node.js unit-http module ..."
	$(MAKE) -C unit node-local-install DESTDIR=../hw

GO_MODULE=unit/build/go/src/unit.nginx.org/go/env.go

$(GO_MODULE): | unit/build/.configure
	@echo "Installing Go unit-http module ..."
	$(MAKE) -C unit go-install


%_c: %.c $(LIBUNIT)
	@echo "Compiling C application ..."
	$(CC) -o $@ $< -I unit/src -I unit/build -L unit/build -lunit -pthread

%.class: %.java | unit/build/.configure
	@echo "Compiling Java application ..."
	javac -target 8 -source 8 -classpath unit/build/tomcat-servlet-api-9.0.39.jar -Xlint:deprecation $<

%_go: %.go $(LIBUNIT) $(GO_MODULE)
	@echo "Compiling Go application ..."
	GOPATH=$(shell pwd)/unit/build/go go build -a -o $@ $<


hw/venv:
	@echo "Creating Python virtual environment ..."
	python3.8 -m venv $@

hw/venv/.uvloop: | hw/venv
	@echo "Installing Python uvloop ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uvloop
	touch $@

hw/venv/.uvicorn: | hw/venv
	@echo "Installing Python uvicorn ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uvicorn[standard]
	touch $@

hw/venv/.uwsgi: | hw/venv
	@echo "Installing Python uwsgi ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uwsgi
	touch $@


hw/$(JETTY_NAME)-$(JETTY_VER): hw/$(JETTY_TAR)
	tar -C hw -xzf $<

hw/$(JETTY_TAR):
	curl -o "$@" "$(JETTY_URL)"

hw/jhw-base:
	@echo "Preparing jhw-base ..."
	mkdir -p $@/webapps
	echo '--module=server' > $@/start.ini
	echo '--module=deploy' >> $@/start.ini
	echo '--module=websocket' >> $@/start.ini
	echo '--module=http' >> $@/start.ini
	echo 'jetty.http.port=8004' >> $@/start.ini

hw/jhw-base/webapps/$(JHW_CLASS): hw/$(JHW_CLASS) | hw/jhw-base
	cp -r hw/jhw hw/jhw-base/webapps/


wrk:
	@echo "Fetching wrk sources from GitHub ..."
	git clone https://github.com/wg/wrk.git

wrk/wrk: | wrk
	@echo "Compiling wrk ..."
	$(MAKE) -C wrk
