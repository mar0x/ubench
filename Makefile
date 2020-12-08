# vim:ts=4:sts=4:sw=4:noet

CFLAGS=-O3
LDFLAGS=

COPT=--cc-opt=$(CFLAGS) --control=127.0.0.1:8443 --openssl --ld-opt=$(LDFLAGS)
COPT+=--modules=build --state=build --tmp=build --tests

HW_LIST = hw/hw_c hw/hw_go hw/jhw/WEB-INF/classes/app.class \
    hw/venv hw/venv/.uvloop hw/venv/.uvicorn hw/venv/.uwsgi
NODE_MODULE = hw/node_modules/unit-http/build/Release/unit-http.node
LIBUNIT = unit/build/libunit.a

.PHONY: all clean

all: unit/build/unitd $(HW_LIST) $(NODE_MODULE)

unit:
	@echo "Fetching Unit source from repo ..."
	hg clone http://hg.nginx.org/unit

unit/.patched: patches | unit
	@echo "Applying patches ..."
	cd unit && \
	for p in ../patches/*.patch; do patch -p1 -i $$p; done && \
	touch .patched

clean: stop
	@echo "Cleaning all staff ..."
	rm -rf unit hw/node_modules/unit-http $(HW_LIST) hw/__pycache__

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
	./configure nodejs && touch build/.configure

.NOTPARALLEL: unit/build/unitd $(LIBUNIT)

unit/build/unitd $(LIBUNIT) &: unit/build/.configure
	@echo "Compiling Unit and modules ..."
	$(MAKE) -C unit all build/libunit.a

unit/ctags: | unit
	cd unit && ctags -R src go

.PHONY: start
start: unit/unit.pid hw/uvicorn.pid

unit/unit.pid: SHELL:=/bin/bash

unit/unit.pid: | unit/build/unitd $(HW_LIST) $(NODE_MODULE)
	@echo "Starting Unit ..."
	@cd unit && \
	ulimit -S -n 65536 && \
	( [ -f unit.log ] && mv unit.log unit-`date +'%Y%m%d-%H%M%S'`.log ||: ) && \
	build/unitd
	@( for i in 0 1 2; do sleep 1 && echo -n . ; done ) && echo ""
	@curl -X PUT -d @unit.conf http://127.0.0.1:8443/config
	@ps aux | grep unit | grep -v grep
	@echo "Set router threads CPU affinity ..."
	@rpid=`ps aux | grep -F 'unit: router' | grep -v grep | awk '{ print $$2 }'` && \
	c=7; for p in `ls /proc/$$rpid/task/`; do taskset -c -p $$c $$p >/dev/null; (( c++ )); done
	@echo "Set C-application processes CPU affinity ..."
	@c=0; for p in `ps aux | grep hw_c | grep -v grep | awk '{ print $$2 }'`; do taskset -c -p $$c $$p >/dev/null; (( c++ )); done
	@echo "Set WSGI application processes CPU affinity ..."
	@c=0; for p in `ps aux | grep hw-wsgi | grep -v grep | awk '{ print $$2 }'`; do taskset -c -p $$c $$p >/dev/null; (( c++ )); done
	@echo "Set ASGI (uvloop) application processes CPU affinity ..."
	@c=0; for p in `ps aux | grep hw-asgi-uvloop | grep -v grep | awk '{ print $$2 }'`; do taskset -c -p $$c $$p >/dev/null; (( c++ )); done

hw/uvicorn.pid: SHELL:=/bin/bash

hw/uvicorn.pid: | hw/venv/.uvicorn hw/venv/.uvloop
	@cd hw && source venv/bin/activate && \
	ulimit -S -n 65536 && \
	( uvicorn --host 0.0.0.0 --port 8300 --loop uvloop --no-access-log --workers 8 hw-asgi:application & )
	@( for i in 0 1 2; do sleep 1 && echo -n . ; done ) && echo ""
	@echo "Set uvicorn application processes CPU affinity ..."
	@c=0; for p in `ps aux | grep spawn_main | grep -v grep | awk '{ print $$2 }'`; do taskset -c -p $$c $$p >/dev/null; (( c++ )); done
	@ps aux | grep 'spawn_main\|bin/uvicorn' | grep -v grep | awk '{ print $$2 }' > $@

.PHONY: stop stop-unit stop-uvicorn
.IGNORE: stop stop-unit stop-uvicorn
stop: stop-unit stop-uvicorn

stop-unit:
	@echo "Stopping Unit ..."
	@[ -f unit/unit.pid ] && \
	kill `cat unit/unit.pid` && \
	( for i in 0 1 2; do sleep 1 && echo -n . ; done ) && echo "" && \
	( ps aux | grep unit | grep -v grep ||: )

stop-uvicorn:
	@echo "Stopping uvicorn ..."
	@[ -f hw/uvicorn.pid ] && \
	kill `cat hw/uvicorn.pid` && \
	( for i in 0 1 2; do sleep 1 && echo -n . ; done ) && echo "" && \
	rm -f hw/uvicorn.pid


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

%.class: %.java unit/build/.configure
	@echo "Compiling Java application ..."
	javac -target 8 -source 8 -classpath unit/build/tomcat-servlet-api-9.0.39.jar $<

%_go: %.go $(LIBUNIT) $(GO_MODULE)
	@echo "Compiling Go application ..."
	GOPATH=$(shell pwd)/unit/build/go go build -a -o $@ $<


hw/venv:
	@echo "Creating Python virtual environment ..."
	python3.8 -m venv hw/venv

hw/venv/.uvloop: | hw/venv
	@echo "Installing Python uvloop ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uvloop && \
	touch $@

hw/venv/.uvicorn: | hw/venv
	@echo "Installing Python uvicorn ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uvicorn[standard] && \
	touch $@

hw/venv/.uwsgi: | hw/venv
	@echo "Installing Python uwsgi ..."
	VIRTUAL_ENV=$(shell pwd)/hw/venv ./hw/venv/bin/pip install uwsgi && \
	touch $@


wrk:
	@echo "Fetching wrk sources from Git ..."
	git clone https://github.com/wg/wrk.git

wrk/wrk: | wrk
	@echo "Compiling wrk ..."
	$(MAKE) -C wrk
