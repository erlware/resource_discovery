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

% Store
-export([
         store_local_resources/1,
         store_callback_modules/1,
         store_target_types/1
        ]).

% Delete
-export([
         delete_local_resource/1,
         delete_target_type/1,
         delete_callback_module/1,
         delete_resource/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("macros.hrl").
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
-spec store_target_types([atom()]) -> no_return().
store_target_types([H|_] = TargetTypes) when is_atom(H) ->
    gen_server:call(?SERVER, {store_target_types, TargetTypes}).

%%-----------------------------------------------------------------------
%% @doc Store the "I haves" or local_resources for resource discovery.
%% @end
%%-----------------------------------------------------------------------
-spec store_local_resources([resource_tuple()]) -> ok.
store_local_resources([{_,_}|_] = LocalResourceTuples) ->
    gen_server:call(?SERVER, {store_local_resources, LocalResourceTuples}).

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
-spec delete_local_resource(resource_tuple()) -> true.
delete_local_resource(LocalResourceTuple) ->
    gen_server:call(?SERVER, {delete_local_resource, LocalResourceTuple}).

%%-----------------------------------------------------------------------
%% @doc Remove a resource.
%% @end
%%-----------------------------------------------------------------------
-spec delete_resource(resource_tuple()) -> true.
delete_resource({_,_} = ResourceTuple) ->
    gen_server:call(?SERVER, {delete_resource, ResourceTuple}).

%%--------------------------------------------------------------------
%% @doc inform an rd_core server of local resources and target types.
%%      This will prompt the remote servers to asyncronously send
%%      back remote resource information.
%% @end
%%--------------------------------------------------------------------
-spec trade_resources() -> ok.
trade_resources() ->
    gen_server:cast(?SERVER, trade_resources).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    error_logger:info_msg("~n", []),
    {ok, #state{}}.

handle_call({store_callback_modules, Modules}, _From, State) ->
    rd_store:store_callback_modules(Modules),
    {reply, ok, State};
handle_call({store_target_types, TargetTypes}, _From, State) ->
    rd_store:store_target_types(TargetTypes),
    {reply, ok, State};
handle_call({store_local_resources, LocalResourceTuples}, _From, State) ->
    rd_store:store_local_resources(LocalResourceTuples),
    {reply, ok, State};

handle_call({delete_callback_module, Module}, _From, State) ->
    rd_store:delete_callback_module(Module),
    {reply, ok, State};
handle_call({delete_target_type, TargetType}, _From, State) ->
    rd_store:delete_target_type(TargetType),
    {reply, ok, State};
handle_call({delete_local_resource, LocalResourceTuple}, _From, State) ->
    rd_store:delete_local_resource(LocalResourceTuple),
    {reply, ok, State};
handle_call({delete_resource, ResourceTuple}, _From, State) ->
    rd_store:delete_local_resource(ResourceTuple),
    {reply, ok, State}.

handle_cast(trade_resources, State) ->
    ResourceTuples = rd_store:lookup_local_resources(),
    lists:foreach(
        fun(Node) ->
            gen_server:cast({?SERVER, Node},
                            {trade_resources, {node(), ResourceTuples}})
        end,
        nodes(known)),
    {noreply, State};
handle_cast({trade_resources, {ReplyTo, Remotes}}, State) ->
    Locals = rd_store:lookup_local_resources(),
    TargetTypes = rd_store:lookup_target_types(),
    FilteredRemotes = filter_resource_tuples_by_types(TargetTypes, Remotes),
    rd_store:store_resources(FilteredRemotes),
    make_callbacks(FilteredRemotes),
    case ReplyTo of
        noreply ->
            ok;
        _ ->
            gen_server:cast({?SERVER, ReplyTo},
                            {trade_resources, {noreply, Locals}})
    end,
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
      rd_store:lookup_callback_modules()).
