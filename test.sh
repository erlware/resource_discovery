#!/bin/sh

SUFFIX=`erl -sname a -s init stop | grep @ | sed -e 's/[^@]*\([^)]*\).*/\1/'`

xterm -hold -e rd_test_app -sname a -contact_node a$SUFFIX &
sleep 5
xterm -hold -e rd_test_app -sname b -contact_node a$SUFFIX &
xterm -hold -e rd_test_app -sname c -contact_node a$SUFFIX &
