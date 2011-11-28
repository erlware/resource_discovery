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
-include("../include/resource_discovery.hrl").

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------

% Create
-export([
         new/0,
	 delete/0
        ]).

% Lookup
-export([
         round_robin_get/1,
         get_resources/1,
         get_callback_modules/0,
         get_local_resource_tuples/0,
	 get_deleted_resource_tuples/0,
         get_target_resource_types/0,
         get_num_resource_types/0,
	 get_num_resource/1,
         get_resource_types/0
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_resource_type/1,
         delete_callback_module/1,
         delete_resource_tuple/1,
	 delete_deleted_resource_tuple/0
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
%% temp store for deleted local resources, so we could remove them from remote nodes.
-define(DL, rd_deleted_kv_store).

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
-spec new() -> ok.
new() ->
    ets:new(?RS, [named_table, public]),
    ets:new(?LKVStore, [named_table, public]),
    ok.
 
%%--------------------------------------------------------------------
%% @doc
%% Deletes storage
%% @end
%%--------------------------------------------------------------------
-spec delete() -> ok.
delete() ->
    ets:delete(?RS),
    ets:delete(?LKVStore),
    ok.

%%-----------------------------------------------------------------------
%% @doc Store the callback modules for the local system.
%% @end
%%-----------------------------------------------------------------------
-spec store_callback_modules([atom()]) -> ok.
store_callback_modules([H|_] = Modules) when is_atom(H) ->
    ets:insert(?LKVStore, {callback_modules, lists:usort(get_callback_modules() ++ Modules)}),
    ok.
     
%%-----------------------------------------------------------------------
%% @doc Output the callback modules.
%% @end
%%-----------------------------------------------------------------------
-spec get_callback_modules() -> [atom()].
get_callback_modules() ->
    case ets:lookup(?LKVStore, callback_modules) of
	[{callback_modules, CallBackModules}] -> CallBackModules;
	[] -> []
    end.

%%-----------------------------------------------------------------------
%% @doc Remove a callback module.
%% @end
%%-----------------------------------------------------------------------
-spec delete_callback_module(atom()) -> ok.
delete_callback_module(CallBackModule) ->
    NewCallBackModules = lists:delete(CallBackModule, get_callback_modules()),
    ets:insert(?LKVStore, {callback_modules, NewCallBackModules}),
    ok.

%%-----------------------------------------------------------------------
%% @doc Store the target types for the local system. Store an "I Want"
%%      type. These are the types we wish to find among the node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec store_target_resource_types([atom()]) -> ok.
store_target_resource_types([H|_] = TargetTypes) when is_atom(H) ->
    ets:insert(?LKVStore, {target_types, lists:usort(get_target_resource_types() ++ TargetTypes)}),
    ok.
     
%%-----------------------------------------------------------------------
%% @doc Output the target types. These are the resource types we wish
%%      to find within our node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec get_target_resource_types() -> [atom()].
get_target_resource_types() ->
    case ets:lookup(?LKVStore, target_types) of
	[{target_types, TargetTypes}] -> lists:usort(TargetTypes);
	[] -> []
    end.

%%-----------------------------------------------------------------------
%% @doc Remove a target type.
%% @end
%%-----------------------------------------------------------------------
-spec delete_target_resource_type(atom()) -> ok.
delete_target_resource_type(TargetType) ->
    ets:insert(?LKVStore, {target_types, lists:delete(TargetType, get_target_resource_types())}),
    ok.
	    
%%-----------------------------------------------------------------------
%% @doc Store the "I haves" or local_resources for resource discovery.
%% @end
%%-----------------------------------------------------------------------
-spec store_local_resource_tuples([resource_tuple()]) -> ok.
store_local_resource_tuples([{_,_}|_] = LocalResourceTuples) ->
    ets:insert(?LKVStore, {local_resources, lists:usort(get_local_resource_tuples() ++ LocalResourceTuples)}),
    ok.
     
%%-----------------------------------------------------------------------
%% @doc Output the local resources.
%% @end
%%-----------------------------------------------------------------------
-spec get_local_resource_tuples() -> [resource_tuple()].
get_local_resource_tuples() ->
    case ets:lookup(?LKVStore, local_resources) of
	[{local_resources, LocalResources}] -> LocalResources;
	[] -> []
    end.


%%--------------------------------------------------------------------
%% @doc
%% get resources which we deleted
%% @end
%%--------------------------------------------------------------------
-spec get_deleted_resource_tuples() -> [resource_tuple()].
get_deleted_resource_tuples() ->
    case ets:lookup(?LKVStore, deleted_resources) of
	[{deleted_resources, DeletedResources}] -> DeletedResources;
	[] -> []
    end.
  

%%-----------------------------------------------------------------------
%% @doc Remove a local resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> ok | {error, local_resource_not_found, resource_tuple()}.
delete_local_resource_tuple(LocalResource) ->
    %% first get local resource tuples
    LocalResources = get_local_resource_tuples(),
    %% only add to deleted cache if resource actually exist
    case lists:member(LocalResource, LocalResources) of
	true ->
	    %% store resource to be deleted in delete_cache table, so it could be removed from remote nodes resource cache
	    %% after syching
	    ets:insert(?LKVStore, {deleted_resources, lists:usort(get_deleted_resource_tuples() ++ [LocalResource])}),
	    %% now remove resource
	    ets:insert(?LKVStore, {local_resources, lists:delete(LocalResource, LocalResources)}),
	    ok;
	false -> {error, local_resource_not_found, LocalResource}
    end.

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
	[{Type, Resources}] -> Resources;
	[] -> []
    end.

%%-----------------------------------------------------------------------
%% @doc Adds a new resource.
%% @end
%%-----------------------------------------------------------------------
-spec store_resource_tuple(resource_tuple()) -> ok.
store_resource_tuple({Type, Resource}) when is_atom(Type) ->
    ets:insert(?RS, {Type, lists:usort(get_resources(Type) ++ [Resource])}),
    ok.

-spec store_resource_tuples([resource_tuple()]) -> ok.
store_resource_tuples([]) -> ok;
store_resource_tuples([{_,_}|_] = ResourceTuples) ->
    lists:foreach(fun(ResourceTuple) ->
			  store_resource_tuple(ResourceTuple)
		  end, ResourceTuples).

%%-----------------------------------------------------------------------
%% @doc Remove a single resource from cache.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource_tuple(resource_tuple()) -> ok.
delete_resource_tuple({Type, Resource}) ->
    ets:insert(?RS, {Type, lists:delete(Resource, get_resources(Type))}),
    %% delete Type if it doesnt have any resources
    case get_resources(Type) of
	[] -> ets:match_delete(?RS, {Type, '_'});
	_ -> do_nothing
    end,
    ok.

 
%%--------------------------------------------------------------------
%% @doc
%% clear deleted resource cache. after the network was synched
%% @end
%%--------------------------------------------------------------------
-spec delete_deleted_resource_tuple() -> ok.
delete_deleted_resource_tuple() ->
    ets:insert(?LKVStore, {deleted_resources, []}),
    ok.

    
%%-----------------------------------------------------------------------
%% @doc Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
-spec round_robin_get(resource_type()) -> {ok, resource()} | {error, not_found}.
round_robin_get(Type) ->
    case get_resources(Type) of
	[Resource | RL] ->  
	    ets:insert(?RS, {Type, RL ++ [Resource]}),
	    {ok, Resource};
	[] -> {error, not_found}
    end.

%%-----------------------------------------------------------------------
%% @doc Outputs the number of resource types.
%% @end
%%-----------------------------------------------------------------------
-spec get_num_resource_types() -> integer().
get_num_resource_types() ->
    length(ets:match(?RS, {'$1', '_'})).

%%-----------------------------------------------------------------------
%% @doc Outputs the number of resource types.
%% @end
%%-----------------------------------------------------------------------
-spec get_num_resource(resource_type()) -> integer().
get_num_resource(Type) ->
    case ets:lookup(?RS, Type) of
	[{Type, Resources}] -> length(Resources);
	[] -> 0
    end.

%%-----------------------------------------------------------------------
%% @doc Outputs the types of resources.
%% Return cached resource types
%% @end
%%-----------------------------------------------------------------------
-spec get_resource_types() -> [resource_type()].
get_resource_types() ->
    lists:usort([E || [E] <- ets:match(?RS, {'$1', '_'})]).
