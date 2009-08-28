#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]];
then
    MAKEROOT="sudo"
fi

for i in `cat ../dependencies`
do
    $MAKEROOT cpan $i
done

