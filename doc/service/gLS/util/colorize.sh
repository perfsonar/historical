#!/bin/sh

REGEXP="\&lt;\([^\ &]\+\)\([^\&]*\)\&gt;"

#clear

sed -e "s/$REGEXP/\
\<b style=\"color:blue\"\>\
\&lt;\
\\1\
\<\/b\>\
\<b style=\"color:green\"\>\
\\2\
\<\/b\>\
\<b style=\"color:blue\"\>\
\&gt;\
\<\/b\>\
/g" phase_1.html > phase_1_color.html

