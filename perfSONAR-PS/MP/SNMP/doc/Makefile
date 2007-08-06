IFILE = release.xml
OFILE = release.html
SHEET = /usr/share/xml/docbook/stylesheet/nwalsh/xhtml/docbook.xsl

all: clean
	xsltproc -o $(OFILE) $(SHEET) $(IFILE)

clean:
	rm -frd *.html
