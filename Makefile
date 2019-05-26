import:
	git branch -D master
	cobalt import -b master -m "Site import"

push:
	git push -f origin master:master
