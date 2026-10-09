local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
dofile(dir..'full.lua')
