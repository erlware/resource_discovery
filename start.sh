#!/bin/sh
cd `dirname $0`
exec erl -pa $PWD/ebin -pa $PWD/deps/*/ebin -name rd@127.0.0.1 -setcookie rd -s resource_discovery start -config ebin/sys
