# Compile FFmpeg and all its dependencies to JavaScript.
# You need emsdk environment installed and activated, see:
# <https://kripken.github.io/emscripten-site/docs/getting_started/downloads.html>.

PRE_JS = build/pre.js
POST_JS_SYNC = build/post-sync.js
POST_JS_WORKER = build/post-worker.js

FFMPEG_FILTERS = scale crop select
FFMPEG_DEMUXERS = matroska avi mov flv mpegps asf gif rawvideo rm
FFMPEG_MUXERS = image2
FFMPEG_DECODERS = \
	vp8 vp9 theora \
	mpeg2video mpeg4 h264 hevc \
	wmv1 wmv2 wmv3
FFMPEG_ENCODERS = \
	mjpeg png

FFMPEG_BC = build/ffmpeg/ffmpeg.bc

all: worker node
worker: ffmpeg-worker.js
node: ffmpeg-node.js

clean: clean-js \
	clean-ffmpeg
clean-js:
	rm -f -- ffmpeg*.js
clean-ffmpeg:
	-cd build/ffmpeg && rm -f ffmpeg.bc && make clean

# TODO(Kagami): Emscripten documentation recommends to always use shared
# libraries but it's not possible in case of ffmpeg because it has
# multiple declarations of `ff_log2_tab` symbol. GCC builds FFmpeg fine
# though because it uses version scripts and so `ff_log2_tag` symbols
# are not exported to the shared libraries. Seems like `emcc` ignores
# them. We need to file bugreport to upstream. See also:
# - <https://kripken.github.io/emscripten-site/docs/compiling/Building-Projects.html>
# - <https://github.com/kripken/emscripten/issues/831>
# - <https://ffmpeg.org/pipermail/libav-user/2013-February/003698.html>
FFMPEG_ARGS = \
	--cc=emcc \
	--enable-cross-compile \
	--target-os=none \
	--arch=x86 \
	--disable-runtime-cpudetect \
	--disable-asm \
	--disable-fast-unaligned \
	--disable-pthreads \
	--disable-w32threads \
	--disable-os2threads \
	--disable-debug \
	--disable-stripping \
	\
	--disable-all \
	--enable-ffmpeg \
	--enable-avcodec \
	--enable-avformat \
	--enable-avutil \
	--enable-swscale \
	--enable-avfilter \
	--disable-network \
	--disable-d3d11va \
	--disable-dxva2 \
	--disable-vaapi \
	--disable-vda \
	--disable-vdpau \
	$(addprefix --enable-decoder=,$(FFMPEG_DECODERS)) \
	$(addprefix --enable-demuxer=,$(FFMPEG_DEMUXERS)) \
	$(addprefix --enable-encoder=,$(FFMPEG_ENCODERS)) \
	$(addprefix --enable-muxer=,$(FFMPEG_MUXERS)) \
	--enable-protocol=file \
	$(addprefix --enable-filter=,$(FFMPEG_FILTERS)) \
	--disable-bzlib \
	--disable-iconv \
	--disable-libxcb \
	--disable-lzma \
	--disable-sdl \
	--disable-securetransport \
	--disable-xlib \
	--enable-zlib

build/ffmpeg/ffmpeg.bc: $(MP4_SHARED_DEPS)
	cd build/ffmpeg && \
	git reset --hard && \
	patch -p1 < ../ffmpeg-disable-monotonic.patch && \
	emconfigure ./configure \
		$(FFMPEG_ARGS) \
		&& \
	emmake make -j8 && \
	cp ffmpeg ffmpeg.bc

# Compile bitcode to JavaScript.
# NOTE(Kagami): Bump heap size to 64M, default 16M is not enough even
# for simple tests and 32M tends to run slower than 64M.
EMCC_FFMPEG_ARGS = \
	--closure 1 \
	-s TOTAL_MEMORY=67108864 \
	-s OUTLINING_LIMIT=20000 \
	-O3 --memory-init-file 0 \
	--pre-js $(PRE_JS) \
	-o $@

ffmpeg-node.js: $(FFMPEG_BC) $(PRE_JS) $(POST_JS_SYNC)
	emcc $(FFMPEG_BC) \
		--post-js $(POST_JS_SYNC) \
		$(EMCC_FFMPEG_ARGS)

ffmpeg-worker.js: $(FFMPEG_BC) $(PRE_JS) $(POST_JS_WORKER)
	emcc $(FFMPEG_BC) \
		--post-js $(POST_JS_WORKER) \
		$(EMCC_FFMPEG_ARGS)
