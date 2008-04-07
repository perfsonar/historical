FILE=iperf
VERSION=1.0
HTMLSHEET=/usr/share/xml/docbook/stylesheet/nwalsh/xhtml/docbook.xsl

all: clean html

html: clean
	../../util/inline.pl $(FILE).xml > tmp.$(FILE).xml
	xsltproc -o tmp.$(FILE).html --stringparam appendix.autolabel A --stringparam chapter.autolabel 1 --stringparam part.autolabel I --stringparam reference.autolabel I --stringparam section.autolabel 1 --stringparam toc.section.depth 5 --stringparam section.autolabel.max.depth 5 $(HTMLSHEET) tmp.$(FILE).xml
	../../util/post.pl tmp.$(FILE).html > $(FILE).html
	rm -frd tmp.$(FILE).html
	rm -frd tmp.$(FILE).xml

clean:
	rm -frd *.html
	rm -frd tmp.$(FILE).xml
