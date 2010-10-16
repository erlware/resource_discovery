#!/bin/sh

if [ $1 = "" ];then
	"Enter in the suffix for a node with an sname like <nodename><suffix> as in a@macintosh"
	exit 1
fi

xterm -hold rd_test_app -sname a -contact_node a"$1"
xterm -hold rd_test_app -sname b -contact_node a"$1"
xterm -hold rd_test_app -sname c -contact_node a"$1" 
