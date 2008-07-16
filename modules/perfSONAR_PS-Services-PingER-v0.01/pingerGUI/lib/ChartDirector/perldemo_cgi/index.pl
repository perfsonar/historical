#!/usr/bin/perl
print "Content-type: text/html\n\n";
print <<EndOfHTML
<html>
<head>
<title>ChartDirector Ver 4.1 Sample Programs</title>
</head>
<FRAMESET ROWS="19,*" FRAMESPACING="0">
    <FRAME
      NAME="indextop"
      SRC="indextop.pl"
      SCROLLING="no"
      FRAMEBORDER="YES"
      BORDER="0"
    >
    <FRAMESET COLS="220,*" FRAMESPACING="0">
        <FRAME
                NAME="indexleft"
                SRC="indexleft.pl"
                SCROLLING="auto"
                FRAMEBORDER="YES"
        >
        <FRAME
                NAME="indexright"
                SRC="indexright.pl"
                SCROLLING="auto"
                FRAMEBORDER="YES"
        >
    </FRAMESET>
</FRAMESET>
</html>
EndOfHTML
;
