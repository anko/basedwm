all: bin/index.js wm-kit.js

bin/index.js: index.ls
	@mkdir -p bin
	echo '#!/usr/bin/env node' > $@
	lsc --compile --print $< >> $@
	chmod +x $@

wm-kit.js: wm-kit.ls
	lsc --compile --print $< > $@

clean:
	@rm -f bin/index.js wm-kit.js

.PHONY: all clean
