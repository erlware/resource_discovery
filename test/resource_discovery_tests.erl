-module(resource_discovery_tests).
-compile([export_all]).

-export([resource_up/1, test_adder/2]).

-include_lib("eunit/include/eunit.hrl").

-define(RESOURCE_TUPLES, [{a, a}, {a, b}, {a, b}, {b, a}]).

%% T = [{a, a}, {a, b}, {a, b}, {b, a}].
%% resource_discovery:add_local_resource_tuples(T).
%% resource_discovery:add_target_resource_types([b]).
%% resource_discovery:get_resources(b).

process_test_() ->
    {setup,
     fun start_process/0,
     fun stop_process/1,
     fun run/1}.

start_process() ->
    resource_discovery:start().
stop_process(_P) ->
    resource_discovery:stop(),
    ok.

run(_P) ->
    {inorder,
    [
     %% add local and target resources
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuples(?RESOURCE_TUPLES)),
     ?_assertMatch(ok, resource_discovery:add_target_resource_type(b)),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% check that target resource is avilable
     ?_assertMatch([a], resource_discovery:get_resources(b)),
     ?_assertMatch([b], resource_discovery:get_resource_types()),
     %% delete local resource, the resource should dissapear from remote caches after sych
     ?_assertMatch(ok, resource_discovery:delete_local_resource_tuple({b,a})),
     %% try to remove non existing resource
     ?_assertMatch({error, local_resource_not_found, {b,a1}}, resource_discovery:delete_local_resource_tuple({b,a1})),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% check that it is not avialable to network anymore
     ?_assertMatch([], resource_discovery:get_resources(b)),
     ?_assertMatch([], resource_discovery:get_resources(a)),
     ?_assertMatch({error, not_found}, resource_discovery:get_resource(b)),
     %% check that resource types with no resources is gone  
     ?_assertMatch([], resource_discovery:get_resource_types()),
     %% add new target resources in "I want" list
     ?_assertMatch(ok, resource_discovery:add_target_resource_types([e,f,n])),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuples([{e,e1}, {e,e2}, {e,e3}, {f, f1}])),
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuple({f, f1})),
     ?_assertMatch(ok, resource_discovery:trade_resources()),
     ?_assertMatch([e, f], resource_discovery:get_resource_types()),
     ?_assertEqual(2, resource_discovery:get_num_resource_types()),
     ?_assertEqual(3, resource_discovery:get_num_resource(e)),
     %% number of non-existing resource 
     ?_assertEqual(0, resource_discovery:get_num_resource(k)),
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuples([{b,a}])),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     ?_assertMatch([a], resource_discovery:get_resources(b)),
     ?_assertMatch({ok, a}, resource_discovery:get_resource(b)),
     ?_assertMatch([e1, e2, e3], resource_discovery:get_resources(e)),
     %% delete resource
     ?_assertMatch(ok,resource_discovery:delete_resource_tuple({b,a})),
     %% shouldn't exist in local cache
     ?_assertMatch({error, not_found}, resource_discovery:get_resource(b)),
     ?_assertMatch(ok, resource_discovery:trade_resources()),
     %% ... but deleted resource will reappear after syching
     ?_assertMatch({ok, a}, resource_discovery:get_resource(b)),
     %% need to delete target resource type first, then delete resource from cache
     ?_assertMatch(ok, resource_discovery:delete_target_resource_type(b)),
     ?_assertMatch(ok,resource_discovery:delete_resource_tuple({b,a})),
     ?_assertMatch([e, f], resource_discovery:get_resource_types()),
     ?_assertMatch(ok, resource_discovery:trade_resources()),
     %% now it should be gone
     ?_assertMatch({error, not_found}, resource_discovery:get_resource(b))
    ]}.



%% test call notifications
%% we setup a loop to hold a state, callback will fire up resource_up/1 func, which will set a state of 
%% a loop process, so we can verify this state in unit test.

-record(state, {value = false}).
rd_notification_test_() ->
    {setup,
     fun start_notify_loop/0,
     fun(Pid) -> stop_notify_loop(Pid) end,
     fun run_notify/1}.

start_notify_loop() ->
    resource_discovery:start(),
    Pid = spawn(fun() -> loop(#state{}) end),
    register(notify_loop_process, Pid),
    Pid.
			 
stop_notify_loop(Pid) ->
    resource_discovery:stop(),
    unregister(notify_loop_process),
    Pid ! stop,
    ok.

run_notify(_Pid) ->
    {inorder,
    [
     %% add callback module, local and target resources
     ?_assertMatch(ok, resource_discovery:add_callback_module(?MODULE)),
     ?_assertMatch(ok, resource_discovery:add_target_resource_types([e,f,n])),
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuples([{e,e1}, {f, f1}])),
     %% before synch, there is not notification
     ?_assertEqual(false, get_state()),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% after synch, there should be a notification
     ?_assertEqual(true, get_state()),
     %% now remove the cached resource
     ?_assertMatch(ok,resource_discovery:delete_resource_tuple({e,e1})),
     %% verify that resource is gone
     ?_assertMatch({error, not_found}, resource_discovery:get_resource(e)),
     %% remove notification module and synch 
     ?_assertMatch(ok, resource_discovery:delete_callback_module(?MODULE)),
     %% reset the state of loop process
     ?_assertMatch(ok, set_state(false)),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% verify that notification wasn't sent
     ?_assertEqual(false, get_state()),
     %% verify that resource was still cached
     ?_assertMatch({ok,e1}, resource_discovery:get_resource(e))
    ]}.


%% function which is called when event happens
%% for test we only care when resource 'e' becomes available
resource_up({e, R}) ->
    error_logger:info_msg("resource is up ~p: ~p", [e, R]),
    %% callback happend, set state in loop process, so it could be verified in test
    set_state(true);   
resource_up(Other) ->
    error_logger:info_msg("resource is up, dont' care: ~p", [Other]).

get_state() ->
    notify_loop_process ! {self(), get},
    receive
	Value -> Value
    end.
	     
set_state(Value) ->
    notify_loop_process ! {self(), {set, Value}},
    ok.

loop(State) ->
    receive
	{_From, {set, Value}} -> 
	    loop(State#state{value = Value});
	{From, get} -> 
	    From ! State#state.value,
	    %% reset state back in initial state
	    loop(State#state{value=false});
	stop -> void
    end.
	       

%% rpc_call test
rd_rpc_call_test_() ->
    {setup,
     fun start_adder_loop/0,
     fun stop_adder_loop/1,
     fun rpc_run/1}.

start_adder_loop() ->
    resource_discovery:start().
	 
stop_adder_loop(_P) ->
    resource_discovery:stop().

%% test function to be called by rpc call
test_adder(A, B) when is_integer(A), is_integer(B) ->
    A + B.

rpc_run(_Pid) ->
    Node = node(),
    {inorder,
    [
     %% add local and target resources
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuple({node, Node})),
     ?_assertMatch(ok, resource_discovery:add_local_resource_tuple({node, 'not_existing@nohost'})),
     ?_assertMatch(ok, resource_discovery:add_target_resource_type(node)),
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% add bad node as resource
     ?_assertMatch(['not_existing@nohost', Node], resource_discovery:get_resources(node)),
     ?_assertMatch(5, resource_discovery:rpc_call(node, ?MODULE, test_adder, [1,4])),
     %% bad resource should be deleted now, we should only get live node
     ?_assertMatch({ok, Node}, resource_discovery:get_resource(node)),
     %% try using unknown_resource
     ?_assertMatch({error, not_found}, resource_discovery:rpc_call(unknown_resource, ?MODULE, test_adder, [1,4])),
     %% synch up so bad node is loaded again
     ?_assertMatch(ok, resource_discovery:sync_resources()),
     %% run multicall
     ?_assertMatch({[300],[not_existing@nohost]}, resource_discovery:rpc_multicall(node, ?MODULE, test_adder, [100,200])),
     ?_assertMatch({error, no_resources}, resource_discovery:rpc_multicall(unknown_resource, ?MODULE, test_adder, [400,200]))
    ]}.
