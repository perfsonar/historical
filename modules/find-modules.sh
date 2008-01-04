find -type l -exec grep -e "^use .*;" -e "load [a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*;" {} \; | awk '{ print $2 }' | sed -e 's/;//' | sort | uniq
