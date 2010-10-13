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
         round_robin_get/1,
         index_get/2,
         get_resources/1,
         get_callback_modules/0,
         get_local_resource_tuples/0,
         get_target_types/0,
         get_num_types/0,
         get_types/0
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
         store_local_resource_tuples/1,
         store_callback_modules/1,
         store_target_resource_types/1,
         store_resource_tuples/1,
         store_resource_tuple/1
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
			   lists:concat([get_callback_modules(), Modules])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the callback modules.
%% @end
%%-----------------------------------------------------------------------
-spec get_callback_modules() -> [atom()].
get_callback_modules() ->
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
    NewCallBackModules = lists:delete(CallBackModule, get_callback_modules()),
    ets:insert(?LKVStore, {callback_modules, NewCallBackModules}).

%%-----------------------------------------------------------------------
%% @doc Store the target types for the local system. Store an "I Want"
%%      type. These are the types we wish to find among the node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec store_target_resource_types([atom()]) -> no_return().
store_target_resource_types([H|_] = TargetTypes) when is_atom(H) ->
    ets:insert(?LKVStore, {target_types,
			   lists:concat([get_target_types(), TargetTypes])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the target types. These are the resource types we wish
%%      to find within our node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec get_target_types() -> [atom()].
get_target_types() ->
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
    ets:insert(?LKVStore, {target_types, lists:delete(TargetType, get_target_types())}).
	    
%%-----------------------------------------------------------------------
%% @doc Store the "I haves" or local_resources for resource discovery.
%% @end
%%-----------------------------------------------------------------------
-spec store_local_resource_tuples([resource_tuple()]) -> ok.
store_local_resource_tuples([{_,_}|_] = LocalResourceTuples) ->
    ets:insert(?LKVStore, {local_resources,
			   lists:concat([get_local_resource_tuples(), LocalResourceTuples])}).
     
%%-----------------------------------------------------------------------
%% @doc Output the local resources.
%% @end
%%-----------------------------------------------------------------------
-spec get_local_resource_tuples() -> [resource_tuple()].
get_local_resource_tuples() ->
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
    ets:insert(?LKVStore, {local_resources, lists:delete(LocalResource, get_local_resource_tuples())}).

%%%---------------------------
%%% Network Resource Storage
%%%---------------------------

%%-----------------------------------------------------------------------
%% @doc Outputs a list of all resources for a particular type.
%% @end
%%-----------------------------------------------------------------------
-spec get_resources(resource_type()) -> [resource()].
get_resources(Type) ->
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
-spec store_resource_tuple(resource_tuple()) -> no_return().
store_resource_tuple({Type, Resource}) when is_atom(Type) ->
    ets:insert(?RS, {Type, [Resource|get_resources(Type)]}).

-spec store_resource_tuples([resource_tuple()]) -> no_return().
store_resource_tuples([]) ->
    ok;
store_resource_tuples([{_,_}|_] = ResourceTuples) ->
    lists:foreach(fun(ResourceTuple) ->
			  store_resource_tuple(ResourceTuple)
		  end, ResourceTuples).

%%-----------------------------------------------------------------------
%% @doc Remove a single resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource(resource_tuple()) -> no_return().
delete_resource({Type, Resource}) ->
    ets:insert(?RS, {Type, lists:delete(Resource, get_resources(Type))}).
    
%%-----------------------------------------------------------------------
%% @doc Get a resource of a particular type at a given index. Index
%%      starts at 1. 
%% @end
%%-----------------------------------------------------------------------
-spec index_get(resource_type(), pos_integer()) -> {ok, resource()} | {error, not_found}.
index_get(Type, Index) ->
    get_nth(Index, get_resources(Type)).

get_nth(N, List) when length(List) >= N ->
    {ok, lists:nth(N, List)};
get_nth(_N, _List) ->
    {error, not_found}.

%%-----------------------------------------------------------------------
%% @doc Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
-spec round_robin_get(resource_type()) -> {ok, resource()} | {error, not_found}.
round_robin_get(Type) ->
    case get_resources(Type) of
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
get_num_types() ->
    length(ets:match(?RS, {'$1', '_'})).

%%-----------------------------------------------------------------------
%% @doc Outputs the types of resources.
%% @end
%%-----------------------------------------------------------------------
get_types() ->
    [E || [E] <- ets:match(?RS, {'$1', '_'})].

%%%=====================================================================
%%% Testing functions
%%%=====================================================================

get_callback_modules_test() ->
    new(),
    store_callback_modules([a, b]),
    ?assertMatch([a, b], get_callback_modules()),
    delete_callback_module(a),
    ?assertMatch([b], get_callback_modules()).

get_resources_test() ->
    store_resource_tuples([{a, a}, {a, b}, {b, a}]),
    ?assertMatch([{a, a}, {a, b}], get_resources(a)),
    delete_resource({a, a}),
    ?assertMatch([{a, b}], get_resources(a)).
    
get_local_resource_tuples_test() ->
    store_local_resource_tuples([{a, a}, {a, b}, {b, a}]),
    ?assertMatch([{a, a}, {a, b}, {b, a}], get_local_resource_tuples()),
    delete_local_resource({a, a}),
    ?assertMatch([{a, b}, {b, a}], get_local_resource_tuples()).
    
get_target_types_test() ->
    store_target_resource_types([a, b]),
    ?assertMatch([a, b], get_target_types()),
    delete_target_type(a),
    ?assertMatch([b], get_target_types()).


