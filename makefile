index.js: index.ls
	echo '#!/usr/bin/env node' > $@
	lsc --compile --print $< >> $@
	chmod +x $@

clean:
	@rm -f index.js

.PHONY: clean
