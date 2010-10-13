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
	 trade_resources/0
	]).

% Fetch
-export([
	 index_get/2,
	 round_robin_get/1
	]).

% Store
-export([
         store_local_resource_tuples/1,
         store_callback_modules/1,
         store_target_resource_types/1
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_type/1,
         delete_callback_module/1,
         delete_resource_tuple/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("resource_discovery.hrl").

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
-spec delete_target_type(atom()) -> true.
delete_target_type(TargetType) ->
    gen_server:call(?SERVER, {delete_target_type, TargetType}).

%%-----------------------------------------------------------------------
%% @doc Remove a local resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> true.
delete_local_resource_tuple(LocalResourceTuple) ->
    gen_server:call(?SERVER, {delete_local_resource_tuple, LocalResourceTuple}).

%%-----------------------------------------------------------------------
%% @doc Remove a resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource_tuple(resource_tuple()) -> true.
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
%% @doc Gets resource of a particular type outputs and places it in last position.
%% @end
%%-----------------------------------------------------------------------
-spec round_robin_get(resource_type()) -> {ok, resource()} | {error, not_found}.
round_robin_get(Type) ->
    gen_server:call(?SERVER, {round_robin_get, Type}).

%%-----------------------------------------------------------------------
%% @doc Get a resource of a particular type at a given index. Index
%%      starts at 1. 
%% @end
%%-----------------------------------------------------------------------
-spec index_get(resource_type(), pos_integer()) -> {ok, resource()} | {error, not_found}.
index_get(Type, Index) ->
    gen_server:call(?SERVER, {index_get, {Type, Index}}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    error_logger:info_msg("~n", []),
    {ok, #state{}}.

handle_call({round_robin_get, Type}, _From, State) ->
    Reply = rd_store:round_robin_get(Type),
    {reply, Reply, State};
handle_call({index_get, {Type, Index}}, _From, State) ->
    Reply = rd_store:index_get(Type, Index),
    {reply, Reply, State};
handle_call({store_callback_modules, Modules}, _From, State) ->
    rd_store:store_callback_modules(Modules),
    {reply, ok, State};
handle_call({store_target_resource_types, TargetTypes}, _From, State) ->
    rd_store:store_target_resource_types(TargetTypes),
    {reply, ok, State};
handle_call({store_local_resource_tuples, LocalResourceTuples}, _From, State) ->
    rd_store:store_local_resource_tuples(LocalResourceTuples),
    {reply, ok, State};

handle_call({delete_callback_module, Module}, _From, State) ->
    rd_store:delete_callback_module(Module),
    {reply, ok, State};
handle_call({delete_target_type, TargetType}, _From, State) ->
    rd_store:delete_target_type(TargetType),
    {reply, ok, State};
handle_call({delete_local_resource_tuple, LocalResourceTuple}, _From, State) ->
    rd_store:delete_local_resource_tuple(LocalResourceTuple),
    {reply, ok, State};
handle_call({delete_resource_tuple, ResourceTuple}, _From, State) ->
    rd_store:delete_local_resource_tuple(ResourceTuple),
    {reply, ok, State}.

handle_cast(trade_resources, State) ->
    ResourceTuples = rd_store:get_local_resource_tuples(),
    lists:foreach(
        fun(Node) ->
            gen_server:cast({?SERVER, Node},
                            {trade_resources, {node(), ResourceTuples}})
        end,
        nodes(known)),
    {noreply, State};
handle_cast({trade_resources, {ReplyTo, Remotes}}, State) ->
    error_logger:info_msg("got remotes ~p~n", [Remotes]),
    Locals = rd_store:get_local_resource_tuples(),
    TargetTypes = rd_store:get_target_types(),
    FilteredRemotes = filter_resource_tuples_by_types(TargetTypes, Remotes),
    error_logger:info_msg("got remotes and filtered ~p~n", [FilteredRemotes]),
    rd_store:store_resource_tuples(FilteredRemotes),
    make_callbacks(FilteredRemotes),
    reply(ReplyTo, Locals),
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    error_logger:info_msg("", []),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
%% @doc return a list of resources that have a resource_type() found in the target
%%      types list.
%% @end
filter_resource_tuples_by_types(TargetTypes, Resources) ->
    Fun = 
	fun({Type, _Instance} = Resource, Acc) ->
		case lists:member(Type, TargetTypes) of
		    true  -> [Resource|Acc];
		    false -> Acc
		end
	end,
    lists:foldl(Fun, [], Resources).

%% @private
%% @doc call each callback function for each new resource in its own process.
make_callbacks(NewResources) ->
    lists:foreach(
      fun(Module) ->
	      lists:foreach(fun(Resource) ->
				    spawn(fun() -> Module:resource_up(Resource) end) end,
			    NewResources)
      end,
      rd_store:get_callback_modules()).

reply(noreply, _LocalResources) ->
    ok;
reply(_ReplyTo, []) ->
    ok;
reply(ReplyTo, LocalResources) ->
    gen_server:cast({?SERVER, ReplyTo},
		    {trade_resources, {noreply, LocalResources}}).
