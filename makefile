bin/index.js: index.ls
	@mkdir -p bin
	echo '#!/usr/bin/env node' > $@
	lsc --compile --print $< >> $@
	chmod +x $@

clean:
	@rm -f index.js

.PHONY: clean
