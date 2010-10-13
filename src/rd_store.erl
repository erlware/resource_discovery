%%%-------------------------------------------------------------------
%%% File    : rd_store.erl
%%% Author  : Martin J. Logan <martin@gdubya.botomayo>
%%% @doc The storage management functions for resource discovery
%%% @end
%%%-------------------------------------------------------------------
-module(rd_store).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("resource_discovery.hrl").
-include("eunit.hrl").

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------

% Create
-export([
         new/0
        ]).

% Lookup
-export([
         round_robin_lookup/1,
         index_lookup/2,
         lookup_callback_modules/0,
         lookup_local_resources/0,
         lookup_target_types/0,
         lookup_num_types/0,
         lookup_types/0
        ]).

% Delete
-export([
         delete_local_resource/1,
         delete_target_type/1,
         delete_callback_module/1,
         delete_resource/1
        ]).

% Store
-export([
         store_local_resources/1,
         store_callback_modules/1,
         store_target_types/1,
         store_resources/1,
         store_resource/1
        ]).

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(LKVStore, rd_local_kv_store).
-define(RS, rd_resource_store).

%%====================================================================
%% External functions
%%====================================================================

%%%---------------------------
%%% Local Type, Target type Storage
%%%---------------------------

%%-----------------------------------------------------------------------
%% @doc LPS stands for "Local Parameter Store".
%% Initialises persistent storage.
%% @end
%%-----------------------------------------------------------------------
new() ->
    ets:new(?RS, [named_table, public]),
    ets:new(?LKVStore, [named_table, public]).

%%-----------------------------------------------------------------------
%% @doc Store the callback modules for the local system.
%% @end
%%-----------------------------------------------------------------------
-spec store_callback_modules([atom()]) -> no_return().
store_callback_modules([H|_] = Modules) when is_atom(H) ->
    ets:insert(?LKVStore, {callback_modules,
			   lists:concat([lookup_callback_modules(), Modules])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the callback modules.
%% @end
%%-----------------------------------------------------------------------
-spec lookup_callback_modules() -> [atom()].
lookup_callback_modules() ->
    case ets:lookup(?LKVStore, callback_modules) of
	[{callback_modules, CallBackModules}] ->
	    CallBackModules;
	[] ->
	    []
    end.

%%-----------------------------------------------------------------------
%% @doc Remove a callback module.
%% @end
%%-----------------------------------------------------------------------
-spec delete_callback_module(atom()) -> true.
delete_callback_module(CallBackModule) ->
    NewCallBackModules = lists:delete(CallBackModule, lookup_callback_modules()),
    ets:insert(?LKVStore, {callback_modules, NewCallBackModules}).

%%-----------------------------------------------------------------------
%% @doc Store the target types for the local system. Store an "I Want"
%%      type. These are the types we wish to find among the node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec store_target_types([atom()]) -> no_return().
store_target_types([H|_] = TargetTypes) when is_atom(H) ->
    ets:insert(?LKVStore, {target_types,
			   lists:concat([lookup_target_types(), TargetTypes])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the target types. These are the resource types we wish
%%      to find within our node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec lookup_target_types() -> [atom()].
lookup_target_types() ->
    case ets:lookup(?LKVStore, target_types) of
	[{target_types, TargetTypes}] ->
	    TargetTypes;
	[] ->
	    []
    end.

%%-----------------------------------------------------------------------
%% @doc Remove a target type.
%% @end
%%-----------------------------------------------------------------------
-spec delete_target_type(atom()) -> true.
delete_target_type(TargetType) ->
    ets:insert(?LKVStore, {target_types, lists:delete(TargetType, lookup_target_types())}).
	    
%%-----------------------------------------------------------------------
%% @doc Store the "I haves" or local_resources for resource discovery.
%% @end
%%-----------------------------------------------------------------------
-spec store_local_resources([resource_tuple()]) -> ok.
store_local_resources([{_,_}|_] = LocalResourceTuples) ->
    ets:insert(?LKVStore, {local_resources,
			   lists:concat([lookup_local_resources(), LocalResourceTuples])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the local resources.
%% @end
%%-----------------------------------------------------------------------
-spec lookup_local_resources() -> [resource_tuple()].
lookup_local_resources() ->
    case ets:lookup(?LKVStore, local_resources) of
	[{local_resources, LocalResources}] ->
	    LocalResources;
	[] ->
	    []
    end.

%%-----------------------------------------------------------------------
%% @doc Remove a local resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_local_resource(resource_tuple()) -> true.
delete_local_resource(LocalResource) ->
    ets:insert(?LKVStore, {local_resources, lists:delete(LocalResource, lookup_local_resources())}).

%%%---------------------------
%%% Network Resource Storage
%%%---------------------------

%%-----------------------------------------------------------------------
%% @doc Outputs a list of all resources for a particular type.
%% @end
%%-----------------------------------------------------------------------
-spec lookup_resources(resource_type()) -> [resource()].
lookup_resources(Type) ->
    case ets:lookup(?RS, Type) of
	[{Type, Resources}] ->
	    Resources;
	[] ->
	    []
    end.

%%-----------------------------------------------------------------------
%% @doc Adds a new resource.
%% @end
%%-----------------------------------------------------------------------
-spec store_resource(resource_tuple()) -> no_return().
store_resource({Type, Resource}) when is_atom(Type) ->
    ets:insert(?RS, {Type, [Resource|lookup_resources(Type)]}).

-spec store_resources([resource_tuple()]) -> no_return().
store_resources([{_,_}|_] = ResourceTuples) ->
    lists:foreach(fun(ResourceTuple) ->
			  store_resource(ResourceTuple)
		  end, ResourceTuples).

%%-----------------------------------------------------------------------
%% @doc Remove a single resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource(resource_tuple()) -> no_return().
delete_resource({Type, Resource}) ->
    ets:insert(?RS, {Type, lists:delete(Resource, lookup_resources(Type))}).
    
%%-----------------------------------------------------------------------
%% @doc Get a resource of a particular type at a given index. Index
%%      starts at 1. 
%% @end
%%-----------------------------------------------------------------------
-spec index_lookup(resource_type(), pos_integer()) -> {ok, resource()} | {error, not_found}.
index_lookup(Type, Index) ->
    get_nth(Index, lookup_resources(Type)).

get_nth(N, List) when length(List) >= N ->
    {ok, lists:nth(N, List)};
get_nth(_N, _List) ->
    {error, not_found}.

%%-----------------------------------------------------------------------
%% @doc Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
-spec round_robin_lookup(resource_type()) -> {ok, resource()} | {error, not_found}.
round_robin_lookup(Type) ->
    case lookup_resources(Type) of
	[Resource|RL] ->
	    ets:insert(?RS, {Type, RL ++ [Resource]}),
	    {ok, Resource};
	[] ->
	    {error, not_found}
    end.

%%-----------------------------------------------------------------------
%% @doc Outputs the number of resource types.
%% @end
%%-----------------------------------------------------------------------
lookup_num_types() ->
    length(ets:match(?RS, {'$1', '_'})).

%%-----------------------------------------------------------------------
%% @doc Outputs the types of resources.
%% @end
%%-----------------------------------------------------------------------
lookup_types() ->
    [E || [E] <- ets:match(?RS, {'$1', '_'})].

%%%=====================================================================
%%% Testing functions
%%%=====================================================================

lookup_callback_modules_test() ->
    new(),
    store_callback_modules([a, b]),
    ?assertMatch([a, b], lookup_callback_modules()),
    delete_callback_module(a),
    ?assertMatch([b], lookup_callback_modules()).
    
lookup_local_resources_test() ->
    store_local_resources([{a, a}, {a, b}, {b, a}]),
    ?assertMatch([{a, a}, {a, b}, {b, a}], lookup_local_resources()),
    delete_local_resource({a, a}),
    ?assertMatch([{a, b}, {b, a}], lookup_local_resources()).
    
lookup_target_types_test() ->
    store_target_types([a, b]),
    ?assertMatch([a, b], lookup_target_types()),
    delete_target_type(a),
    ?assertMatch([b], lookup_target_types()).

lookup_resources_test() ->
    store_resources([{a, a}, {a, b}, {b, a}]),
    ?assertMatch([{a, a}, {a, b}], lookup_resources(a)),
    delete_resource({a, a}),
    ?assertMatch([{a, b}], lookup_resources(a)).
