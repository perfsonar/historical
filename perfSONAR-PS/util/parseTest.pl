#!/usr/bin/perl -w -I ../lib

use strict;
use XML::SAX::ParserFactory;
use Data::Stack;
use perfSONAR_PS::XML::Handler;
use perfSONAR_PS::XML::Element;

# set up the stack
my $stack = new Data::Stack();
my $sentinal = new perfSONAR_PS::XML::Element();
$sentinal->setParent($sentinal);
$stack->push($sentinal);

# parse with a custom handler
my $handler = perfSONAR_PS::XML::Handler->new($stack);
my $p = XML::SAX::ParserFactory->parser(Handler => $handler);
$p->parse_uri("store.xml");

#get the element containing the parse info
my $element = $stack->peek()->getChildByIndex(0);

#print the element
$element->print();
