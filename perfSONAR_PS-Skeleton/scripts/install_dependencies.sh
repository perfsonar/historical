#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]]; then
    MAKEROOT="sudo "
fi

#$MAKEROOT cpan DBI
