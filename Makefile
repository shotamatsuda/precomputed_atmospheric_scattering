# Copyright (c) 2017 Eric Bruneton
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

ifeq ($(OS),Windows_NT)
    UNAME := Windows
else
    UNAME := $(shell uname)
endif

GPP := g++
GPP_FLAGS := -Wall -Wmain -pedantic -pedantic-errors -std=c++11
INCLUDE_FLAGS := \
    -I. -Iexternal -Iexternal/dimensional_types -Iexternal/glad/include \
    -Iexternal/progress_bar
DEBUG_FLAGS := -g
RELEASE_FLAGS := -DNDEBUG -O3 -fexpensive-optimizations

DIRS := atmosphere text tools
HEADERS := $(shell find $(DIRS) -name "*.h")
SOURCES := $(shell find $(DIRS) -name "*.cc")
GLSL_SOURCES := $(shell find $(DIRS) -name "*.glsl")
JS_SOURCES := $(shell find $(DIRS) -name "*.js")
DOC_SOURCES := $(HEADERS) $(SOURCES) $(GLSL_SOURCES) $(JS_SOURCES) index

ifeq ($(UNAME),Windows)
    GL_FLAGS := -lglut -lGL
    GLAD_OBJS := output/Debug/external/glad/src/glad.o
    SED := sed
else
    # See: https://stackoverflow.com/a/19072984
    GPP_FLAGS := $(GPP_FLAGS) -D__gl_h_ -DGL_DO_NOT_WARN_IF_MULTI_GL_VERSION_HEADERS_INCLUDED
    GL_FLAGS := -framework OpenGL -framework GLUT
    GLAD_OBJS :=
    SED := gsed
endif

all: lint doc test integration_test webgl demo

# cpplint can be installed with "pip install cpplint".
# We exclude runtime/references checking for functions.h and model_test.cc
# because we can't avoid using non-const references in these files, due to the
# constraints of double C++/GLSL compilation of functions.glsl.
# We also exclude build/c++11 checking for docgen_main.cc to allow the use of
# <regex>.
lint: $(HEADERS) $(SOURCES)
	cpplint --exclude=tools/docgen_main.cc \
            --exclude=atmosphere/reference/functions.h \
            --exclude=atmosphere/reference/model_test.cc --root=$(PWD) $^
	cpplint --filter=-runtime/references --root=$(PWD) \
            atmosphere/reference/functions.h \
            atmosphere/reference/model_test.cc
	cpplint --filter=-build/c++11 --root=$(PWD) tools/docgen_main.cc

doc: $(DOC_SOURCES:%=output/Doc/%.html)

test: output/Debug/atmosphere_test
	output/Debug/atmosphere_test

integration_test: output/Release/atmosphere_integration_test
	mkdir -p output/Doc/atmosphere/reference
	output/Release/atmosphere_integration_test

webgl: output/Doc/scattering.bin output/Doc/demo.html output/Doc/demo.js

demo: output/Debug/atmosphere_demo
	output/Debug/atmosphere_demo

clean:
	rm -f $(GLSL_SOURCES:%=%.inc)
	rm -rf output/Debug output/Release output/Doc

output/Doc/%.html: % output/Debug/tools/docgen tools/docgen_template.html
	mkdir -p $(@D)
	output/Debug/tools/docgen $< tools/docgen_template.html $@

output/Doc/scattering.bin: output/Debug/precompute
	mkdir -p $(@D)
	output/Debug/precompute $(@D)/

output/Doc/demo.html: atmosphere/demo/webgl/demo.html
	mkdir -p $(@D)
	cp $< $@

output/Doc/demo.js: atmosphere/demo/webgl/demo.js
	mkdir -p $(@D)
	cp $< $@

output/Debug/tools/docgen: output/Debug/tools/docgen_main.o
	$(GPP) $< -o $@

output/Debug/atmosphere_test: \
    output/Debug/atmosphere/reference/functions.o \
    output/Debug/atmosphere/reference/functions_test.o \
    output/Debug/external/dimensional_types/test/test_main.o
	$(GPP) $^ -o $@

output/Release/atmosphere_integration_test: \
    output/Release/atmosphere/model.o \
    output/Release/atmosphere/reference/functions.o \
    output/Release/atmosphere/reference/model.o \
    output/Release/atmosphere/reference/model_test.o \
    output/Release/external/dimensional_types/test/test_main.o \
    output/Release/external/glad/src/glad.o \
    output/Release/external/progress_bar/util/progress_bar.o
	$(GPP) $^ -pthread -ldl $(GL_FLAGS) -o $@

output/Debug/precompute: \
    output/Debug/atmosphere/demo/demo.o \
    output/Debug/atmosphere/demo/webgl/precompute.o \
    output/Debug/atmosphere/model.o \
    output/Debug/text/text_renderer.o \
    $(GLAD_OBJS)
	$(GPP) $^ -pthread -ldl $(GL_FLAGS) -o $@

output/Debug/atmosphere_demo: \
    output/Debug/atmosphere/demo/demo.o \
    output/Debug/atmosphere/demo/demo_main.o \
    output/Debug/atmosphere/model.o \
    output/Debug/text/text_renderer.o \
    $(GLAD_OBJS)
	$(GPP) $^ -pthread -ldl $(GL_FLAGS) -o $@

output/Debug/%.o: %.cc
	mkdir -p $(@D)
	$(GPP) $(GPP_FLAGS) $(INCLUDE_FLAGS) $(DEBUG_FLAGS) -c $< -o $@

output/Release/%.o: %.cc
	mkdir -p $(@D)
	$(GPP) $(GPP_FLAGS) $(INCLUDE_FLAGS) $(RELEASE_FLAGS) -c $< -o $@

output/Debug/atmosphere/model.o output/Release/atmosphere/model.o: \
    atmosphere/definitions.glsl.inc \
    atmosphere/functions.glsl.inc

output/Debug/atmosphere/reference/model_test.o \
output/Release/atmosphere/reference/model_test.o: \
    atmosphere/definitions.glsl.inc \
    atmosphere/reference/model_test.glsl.inc

output/Debug/atmosphere/demo/demo.o output/Release/atmosphere/demo/demo.o: \
    atmosphere/demo/demo.glsl.inc

%.glsl.inc: %.glsl
	$(SED) -e '1i const char $(*F)_glsl[] = R"***(' -e '$$a )***";' \
	    -e '/^\/\*/,/\*\/$$/d' -e '/^ *\/\//d' -e '/^$$/d' $< > $@

