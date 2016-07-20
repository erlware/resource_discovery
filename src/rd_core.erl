%%%-------------------------------------------------------------------
%%% @author Martin Logan 
%%% @copyright 2008 Erlware
%%% @doc
%%%   Cache and distribute resources.
%%% @end
%%%-------------------------------------------------------------------
-module(rd_core).

-behaviour(gen_server).

%% API
-export([
	 start_link/0,
	 sync_resources/2,
	 trade_resources/0,
	 filter_resource_tuples_by_types/2,
	 make_callbacks/1
	]).

% Fetch
-export([
	 round_robin_get/1,
	 all_of_type_get/1,
	 get_resource_types/0,
	 get_num_resource_types/0,
	 get_num_resource/1,
	 get_local_resource_tuples/0,
	 get_target_resource_types/0,
	 get_deleted_resource_tuples/0
	]).

% Store
-export([
         store_local_resource_tuples/1,
         store_callback_modules/1,
         store_target_resource_types/1,
	 store_resource_tuples/1
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_resource_type/1,
         delete_callback_module/1,
         delete_resource_tuple/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("../include/resource_discovery.hrl").

-define(SERVER, ?MODULE). 

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc call each subscribed callback function for each new
%%      resource supplied.
%% @end
%%--------------------------------------------------------------------
-spec make_callbacks([resource_tuple()]) -> ok.
make_callbacks(NewResources) ->
    lists:foreach(
      fun(Module) ->
	      lists:foreach(fun(Resource) ->
				    spawn(fun() -> Module:resource_up(Resource) end) end,
			    NewResources)
      end,
      rd_store:get_callback_modules()).

%%--------------------------------------------------------------------
%% @doc return a list of resources that have a resource_type() found in the target
%%      types list.
%% @end
%%--------------------------------------------------------------------
-spec filter_resource_tuples_by_types([resource_type()], [resource_tuple()]) -> [resource_tuple()].
filter_resource_tuples_by_types(TargetTypes, Resources) ->
    Fun = 
	fun({Type, _Instance} = Resource, Acc) ->
		case lists:member(Type, TargetTypes) of
		    true  -> [Resource|Acc];
		    false -> Acc
		end
	end,
    lists:foldl(Fun, [], Resources).


%%-----------------------------------------------------------------------
%% @doc Store the callback modules for the local system.
%% @end
%%-----------------------------------------------------------------------
-spec store_callback_modules([atom()]) -> no_return().
store_callback_modules([H|_] = Modules) when is_atom(H) ->
    gen_server:call(?SERVER, {store_callback_modules, Modules}).

%%-----------------------------------------------------------------------
%% @doc Store the target types for the local system. Store an "I Want"
%%      type. These are the types we wish to find among the node cluster.
%% @end
%%-----------------------------------------------------------------------
-spec store_target_resource_types([atom()]) -> no_return().
store_target_resource_types([H|_] = TargetTypes) when is_atom(H) ->
    gen_server:call(?SERVER, {store_target_resource_types, TargetTypes}).

%%-----------------------------------------------------------------------
%% @doc Store the "I haves" or local_resources for resource discovery.
%% @end
%%-----------------------------------------------------------------------
-spec store_local_resource_tuples([resource_tuple()]) -> ok.
store_local_resource_tuples([{_,_}|_] = LocalResourceTuples) ->
    gen_server:call(?SERVER, {store_local_resource_tuples, LocalResourceTuples}).


-spec store_resource_tuples([resource_tuple()]) -> ok.
store_resource_tuples(Resource) ->
    gen_server:call(?SERVER, {store_resource_tuples, Resource}).

%%-----------------------------------------------------------------------
%% @doc Remove a callback module.
%% @end
%%-----------------------------------------------------------------------
-spec delete_callback_module(atom()) -> true.
delete_callback_module(CallBackModule) ->
    gen_server:call(?SERVER, {delete_callback_module, CallBackModule}).

%%-----------------------------------------------------------------------
%% @doc Remove a target type.
%% @end
%%-----------------------------------------------------------------------
-spec delete_target_resource_type(atom()) -> true.
delete_target_resource_type(TargetType) ->
    gen_server:call(?SERVER, {delete_target_resource_type, TargetType}).

%%-----------------------------------------------------------------------
%% @doc Remove a local resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> ok | {error, local_resource_not_found, resource_tuple()}.
delete_local_resource_tuple(LocalResourceTuple) ->
    gen_server:call(?SERVER, {delete_local_resource_tuple, LocalResourceTuple}).

%%-----------------------------------------------------------------------
%% @doc Remove a resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource_tuple(resource_tuple()) -> ok.
delete_resource_tuple({_,_} = ResourceTuple) ->
    gen_server:call(?SERVER, {delete_resource_tuple, ResourceTuple}).

%%--------------------------------------------------------------------
%% @doc inform an rd_core server of local resources and target types.
%%      This will prompt the remote servers to asyncronously send
%%      back remote resource information.
%% @end
%%--------------------------------------------------------------------
-spec trade_resources() -> ok.
trade_resources() ->
    gen_server:cast(?SERVER, trade_resources).

%%-----------------------------------------------------------------------
%% @doc
%% Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
-spec round_robin_get(resource_type()) -> {ok, resource()} | {error, not_found}.
round_robin_get(Type) ->
    gen_server:call(?SERVER, {round_robin_get, Type}).
 
%%--------------------------------------------------------------------
%% @doc
%% Gets all cached resources of a given type
%% @end
%%--------------------------------------------------------------------
-spec all_of_type_get(resource_type()) -> [resource()].
all_of_type_get(Type) ->
    gen_server:call(?SERVER, {all_of_type_get, Type}).

%%-----------------------------------------------------------------------
%% @doc Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
%%-spec sync_resources(node(), {LocalResourceTuples, TargetTypes, DeletedTuples}) -> ok.
sync_resources(Node, {LocalResourceTuples, TargetTypes, DeletedTuples}) ->
    rd_util:log("synch resources for node: ~p", [Node]),
    {ok, FilteredRemotes} = gen_server:call({?SERVER, Node}, {sync_resources, {LocalResourceTuples, TargetTypes, DeletedTuples}}),
    rd_store:store_resource_tuples(FilteredRemotes),
    make_callbacks(FilteredRemotes),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Get cached resource types
%% @end
%%--------------------------------------------------------------------
-spec get_resource_types() -> [resource_type()].
get_resource_types() ->
    gen_server:call(?SERVER, get_resource_types).

%%------------------------------------------------------------------------------
%% @doc Gets the number of resource types locally cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_num_resource_types() -> integer().
get_num_resource_types() ->
    gen_server:call(?SERVER, get_num_resource_types).

%%--------------------------------------------------------------------
%% @doc
%% get number of cached resources of the given type
%% @end
%%--------------------------------------------------------------------
-spec get_num_resource(resource_type()) -> integer().
get_num_resource(Type) ->
    gen_server:call(?SERVER, {get_num_resource, Type}).

-spec get_local_resource_tuples() -> [resource_tuple()].
get_local_resource_tuples() ->
    gen_server:call(?SERVER, get_local_resource_tuples).

-spec get_target_resource_types() -> [atom()].
get_target_resource_types() ->
    gen_server:call(?SERVER, get_target_resource_types).

%%--------------------------------------------------------------------
%% @doc
%% get resources which we deleted
%% @end
%%--------------------------------------------------------------------
-spec get_deleted_resource_tuples() -> [resource_tuple()].
get_deleted_resource_tuples() ->
    gen_server:call(?SERVER, get_deleted_resource_tuples).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}}.

handle_call({sync_resources, {Remotes, RemoteTargetTypes, RemoteDeletedTuples}}, _From, State) ->
    rd_util:log("sync_resources, got remotes: ~p deleted: ~p", [Remotes, RemoteDeletedTuples]),
    LocalResourceTuples = rd_store:get_local_resource_tuples(),
    TargetTypes = rd_store:get_target_resource_types(),
    FilteredRemotes = filter_resource_tuples_by_types(TargetTypes, Remotes),
    FilteredLocals = filter_resource_tuples_by_types(RemoteTargetTypes, LocalResourceTuples),
    rd_util:log("sync_resources, storing filted remotes: ~p", [FilteredRemotes]),
    rd_store:store_resource_tuples(FilteredRemotes),
    [rd_store:delete_resource_tuple(DR) || DR <- RemoteDeletedTuples],
    make_callbacks(FilteredRemotes),
    {reply, {ok, FilteredLocals}, State};
handle_call({round_robin_get, Type}, _From, State) ->
    Reply = rd_store:round_robin_get(Type),
    {reply, Reply, State};
handle_call({all_of_type_get, Type}, _From, State) ->
    Reply = rd_store:get_resources(Type),
    {reply, Reply, State};
handle_call({store_callback_modules, Modules}, _From, State) ->
    rd_store:store_callback_modules(Modules),
    {reply, ok, State};
handle_call({store_target_resource_types, TargetTypes}, _From, State) ->
    Reply = rd_store:store_target_resource_types(TargetTypes),
    {reply, Reply, State};
handle_call({store_local_resource_tuples, LocalResourceTuples}, _From, State) ->
    Reply = rd_store:store_local_resource_tuples(LocalResourceTuples),
    {reply, Reply, State};
handle_call({store_resource_tuples, Resource}, _From, State) ->
    Reply = rd_store:store_resource_tuples(Resource),
    {reply, Reply, State};
handle_call({delete_callback_module, Module}, _From, State) ->
    rd_store:delete_callback_module(Module),
    {reply, ok, State};
handle_call({delete_target_resource_type, TargetType}, _From, State) ->
    Reply = rd_store:delete_target_resource_type(TargetType),
    {reply, Reply, State};
handle_call({delete_local_resource_tuple, LocalResourceTuple}, _From, State) ->
    Reply = rd_store:delete_local_resource_tuple(LocalResourceTuple),
    {reply, Reply, State};
handle_call({delete_resource_tuple, ResourceTuple}, _From, State) ->
    Reply = rd_store:delete_resource_tuple(ResourceTuple),
    {reply, Reply, State};
handle_call(get_resource_types, _From, State) ->
    Reply = rd_store:get_resource_types(),
    {reply, Reply, State};
handle_call(get_local_resource_tuples, _From, State) ->
    Reply = rd_store:get_local_resource_tuples(),
    {reply, Reply, State};
handle_call(get_target_resource_types, _From, State) ->
    Reply = rd_store:get_target_resource_types(),
    {reply, Reply, State};
handle_call(get_deleted_resource_tuples, _From, State) ->
    Reply = rd_store:get_deleted_resource_tuples(),
    {reply, Reply, State};
handle_call(get_num_resource_types, _From, State) ->
    Reply = rd_store:get_num_resource_types(),
    {reply, Reply, State};
handle_call({get_num_resource, Type}, _From, State) ->
    Reply = rd_store:get_num_resource(Type),
    {reply, Reply, State}.

handle_cast(trade_resources, State) ->
    ResourceTuples = rd_store:get_local_resource_tuples(),
    DeletedTuples = rd_store:get_deleted_resource_tuples(),
    lists:foreach(
        fun(Node) ->
            gen_server:cast({?SERVER, Node},
                            {trade_resources, {node(), {ResourceTuples, DeletedTuples}}})
        end,
        nodes(known)),
    rd_store:delete_deleted_resource_tuple(),
    {noreply, State};
handle_cast({trade_resources, {ReplyTo, {Remotes, RemoteDeletedTuples}}}, State) ->
    rd_util:log("trade_resources, got remotes ~p: deleted: ~p", [Remotes, RemoteDeletedTuples]),
    Locals = rd_store:get_local_resource_tuples(),
    LocalsDeleted = rd_store:get_deleted_resource_tuples(),
    TargetTypes = rd_store:get_target_resource_types(),
    FilteredRemotes = filter_resource_tuples_by_types(TargetTypes, Remotes),
    rd_util:log("got remotes and filtered ~p", [FilteredRemotes]),
    rd_store:store_resource_tuples(FilteredRemotes),
    rd_util:log("trade_resources, deleting ~p", [RemoteDeletedTuples]),
    [rd_store:delete_resource_tuple(DR) || DR <- RemoteDeletedTuples],
    make_callbacks(FilteredRemotes),
    reply(ReplyTo, {Locals, LocalsDeleted}),
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


reply(noreply, {_LocalResources, _LocalsDeleted}) -> ok;
reply(_ReplyTo, {[], []}) -> ok;
reply(ReplyTo, {LocalResources,LocalsDeleted}) ->
    gen_server:cast({?SERVER, ReplyTo}, {trade_resources, {noreply, {LocalResources, LocalsDeleted}}}).
