-module(rd_store_tests).
-compile([export_all]).

-include_lib("eunit/include/eunit.hrl").
-define(TEST_VALUES, [{a, a}, {a, b}, {b, a}]).

rd_store_local_resource_test_() ->
    {setup, local,
     fun rd_store:new/0,
     fun(_Pid) -> rd_store:delete() end,
     fun(_P) ->
	     {inorder,
	      [
	       %% add local resources
	       ?_assertEqual(ok, rd_store:store_local_resource_tuples(?TEST_VALUES)),
	       %% check that we get the same resources from storage
	       ?_assertEqual(?TEST_VALUES, rd_store:get_local_resource_tuples()),
	       %% test for dublicate values
	       ?_assertEqual(ok, rd_store:store_local_resource_tuples([{a,a},{a,b}])),
	       %% shouln't have new resources after dublicate were attempted to add
	       ?_assertEqual(?TEST_VALUES, rd_store:get_local_resource_tuples()),
	       %% remove resource
	       ?_assertEqual(ok, rd_store:delete_local_resource_tuple({a, a})),
	       ?_assertMatch([{a, b}, {b, a}], rd_store:get_local_resource_tuples())
	      ]}
     end }.

rd_store_target_resource_test_() ->
    {setup, local,
     fun rd_store:new/0,
     fun(_Pid) -> rd_store:delete() end,
     fun(_P) ->
	     {inorder,
	      [
	       ?_assertEqual(ok, rd_store:store_target_resource_types([c, d, e])),
	       ?_assertMatch([c,d,e], rd_store:get_target_resource_types()),
	       ?_assertMatch(ok, rd_store:delete_target_resource_type(c)),
	       ?_assertMatch([d,e], rd_store:get_target_resource_types())
	      ]}
     end }.


rd_store_resource_test_() ->
    {setup, local,
     fun rd_store:new/0,
     fun(_Pid) -> rd_store:delete() end,
     fun(_P) ->
	     {inorder,
	      [
	       ?_assertEqual(ok, rd_store:store_resource_tuple({c, c1})),
	       ?_assertEqual(ok, rd_store:store_resource_tuples([{d, d1},{d, d2}, {e, e1}, {e, e2}, {b, b1}])),
	       ?_assertMatch(2, rd_store:get_num_resource(d)),
	       ?_assertMatch(4, rd_store:get_num_resource_types()),
	       ?_assertMatch([b1], rd_store:get_resources(b)),
	       ?_assertMatch([d1, d2], rd_store:get_resources(d)),
	       ?_assertMatch([e1, e2], rd_store:get_resources(e))
	      ]}
     end }.

rd_store_callback_test_() ->
    {setup, local,
     fun rd_store:new/0,
     fun(_Pid) -> rd_store:delete() end,
     fun(_P) ->
	     {inorder,
	      [
	       ?_assertEqual(ok, rd_store:store_callback_modules([a, b])),
	       ?_assertEqual([a,b], rd_store:get_callback_modules()),
	       ?_assertEqual(ok, rd_store:delete_callback_module(a)),
	       ?_assertEqual([b], rd_store:get_callback_modules())	       
	      ]}
     end }.
