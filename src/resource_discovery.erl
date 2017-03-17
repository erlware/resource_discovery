%%%-------------------------------------------------------------------
%%% File    : resource_discovery.erl
%%% Author  : Martin J. Logan <martinjlogan@erlware.org>
%%% @doc
%%% Resource Discovery has 3 major types. They are listed here.
%%% @type resource_tuple() = {resource_type(), resource()}. The type
%%%       of a resource followed by the actual resource. Local
%%%       resource tuples are communicated to other resource discovery
%%%       instances.
%%% @type resource_type() = atom(). The name of a resource, how it is identified. For example
%%%       a type of service that you have on the network may be identified by it's node name
%%%       in which case you might have a resource type of 'my_service' of which there may be
%%%       many node names representing resources such as {my_service, myservicenode@myhost}.
%%% @type resource() =  term(). Either a concrete resource or a reference to one like a pid().
%%% @end
%%%-------------------------------------------------------------------
-module(resource_discovery).

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------

% Standard exports.
-export([
	 start/0,
         start/2,
	 stop/0
        ]).

% Add
-export([
         add_local_resource_tuples/1,
         add_local_resource_tuple/1,
         add_target_resource_types/1,
         add_target_resource_type/1,
         add_callback_modules/1,
         add_callback_module/1
        ]).
% Get
-export([
         get_resource/1,
         get_resources/1,
         get_num_resource/1,
         get_resource_types/0,
         get_num_resource_types/0
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_resource_type/1,
         delete_resource_tuple/1,
	 delete_callback_module/1,
	 delete_callback_modules/1
        ]).

% Other
-export([
         trade_resources/0,
         sync_resources/1,
         sync_resources/0,
         contact_nodes/0,
         rpc_multicall/5,
         rpc_multicall/4,
         rpc_call/5,
         rpc_call/4
        ]).

-include("../include/resource_discovery.hrl").

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(RD, rd_core).

%%====================================================================
%% External functions
%%====================================================================

start() ->
    application:start(resource_discovery).

%%--------------------------------------------------------------------
%% @doc Starts the resource discovery application.
%% @spec start(Type, StartArgs) -> {ok, Pid} | {ok, Pid, State} | {error, Reason}
%% @end
%%--------------------------------------------------------------------
start(_Type, _StartArgs) ->
    % Create the storage for the local parameters; i.e. LocalTypes
    % and TargetTypes.
    random:seed(erlang:timestamp()),
    rd_store:new(),
    rd_sup:start_link().

stop() -> application:stop(resource_discovery).

%%--------------------------------------------------------------------
%% @doc inform an rd_core server of local resources and target types.
%%      This will prompt the remote servers to asyncronously send
%%      back remote resource information.
%% @end
%%--------------------------------------------------------------------
-spec trade_resources() -> ok.
trade_resources() -> rd_core:trade_resources().

%%-----------------------------------------------------------------------
%% @doc Syncronizes resources between the caller and the node supplied.
%%      Like trade resources but this call blocks.
%% @end
%%-----------------------------------------------------------------------
-spec sync_resources(timeout()) -> ok.
sync_resources(Timeout) ->
    sync_locals(),
    Self = self(),
    Nodes = nodes(known),
    %%error_logger:info_msg("synching resources to nodes: ~p", [Nodes]),
    LocalResourceTuples = rd_core:get_local_resource_tuples(),
    DeletedTuples = rd_core:get_deleted_resource_tuples(),
    TargetTypes = rd_core:get_target_resource_types(),

    Pids = [spawn(fun() ->
			  Self ! {'\$sync_resources\$', self(),
				  (catch rd_core:sync_resources(Node, {LocalResourceTuples, TargetTypes, DeletedTuples}))}
		  end)
	    || Node <- Nodes],
    %% resources are synched so remove deleted tuples cache
    rd_store:delete_deleted_resource_tuple(),
    get_responses(Pids, Timeout).

-spec sync_resources() -> ok.
sync_resources() -> sync_resources(10000).

sync_locals() ->
    LocalResourceTuples = rd_core:get_local_resource_tuples(),
    TargetTypes = rd_core:get_target_resource_types(),
    FilteredLocals = rd_core:filter_resource_tuples_by_types(TargetTypes, LocalResourceTuples),
    rd_core:store_resource_tuples(FilteredLocals),
    rd_core:make_callbacks(FilteredLocals).

get_responses([], _Timeout) -> ok;
get_responses(Pids, Timeout) ->
    %% XXX TODO fix the timeout by subracting elapsed time.
    %% XXX TODO perhaps use the response.
    receive
	{'\$sync_resources\$', Pid, _Resp} ->
	    NewPids = lists:delete(Pid, Pids),
	    get_responses(NewPids, Timeout)
    after
	Timeout -> {error, timeout}
    end.

%%------------------------------------------------------------------------------
%% @doc Adds to the list of target types. Target types are the types
%%      of resources that this instance of resource_discovery will cache following
%%      a notification of such a resource from a resource_discovery instance.
%%      This includes the local instance.
%% @end
%%------------------------------------------------------------------------------
-spec add_target_resource_types([resource_type()]) -> ok.
add_target_resource_types([H|_] = TargetTypes) when is_atom(H) ->
    rd_core:store_target_resource_types(TargetTypes).

-spec add_target_resource_type(resource_type()) -> ok.
add_target_resource_type(TargetType) when is_atom(TargetType) ->
    add_target_resource_types([TargetType]).

%%------------------------------------------------------------------------------
%% @doc Adds to the list of local resource tuples.
%% @end
%%------------------------------------------------------------------------------
-spec add_local_resource_tuples([resource_tuple()]) -> ok.
add_local_resource_tuples([{T,_}|_] = LocalResourceTuples) when is_atom(T) ->
    rd_core:store_local_resource_tuples(LocalResourceTuples).

-spec add_local_resource_tuple(resource_tuple()) -> ok.
add_local_resource_tuple({T,_} = LocalResourceTuple) when is_atom(T) ->
    add_local_resource_tuples([LocalResourceTuple]).

%%------------------------------------------------------------------------------
%% @doc Add a callback module or modules to the list of callbacks to be
%%      called upon new resources entering the system.
%% @end
%%------------------------------------------------------------------------------
-spec add_callback_modules([atom()]) -> ok.
add_callback_modules([H|_] = Modules) when is_atom(H) ->
    rd_core:store_callback_modules(Modules).

-spec add_callback_module(atom()) -> ok.
add_callback_module(Module) when is_atom(Module) ->
    add_callback_modules([Module]).

%%------------------------------------------------------------------------------
%% @doc Replies with the cached resource. Round robins though the resources
%%      cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_resource(resource_type()) -> {ok, resource()} | {error, not_found}.
get_resource(Type) when is_atom(Type) ->
    rd_core:round_robin_get(Type).

%%------------------------------------------------------------------------------
%% @doc Returns ALL cached resources for a particular type.
%% @end
%%------------------------------------------------------------------------------
-spec get_resources(resource_type()) -> [resource()].
get_resources(Type) ->
    rd_core:all_of_type_get(Type).

%%------------------------------------------------------------------------------
%% @doc Gets a list of the types that have resources that have been cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_resource_types() -> [resource_type()].
get_resource_types() ->
    rd_core:get_resource_types().

%%------------------------------------------------------------------------------
%% @doc Removes a cached resource from the resource pool. Only returns after the
%%      resource has been deleted.
%% @end
%%------------------------------------------------------------------------------
-spec delete_resource_tuple(resource_tuple()) -> ok.
delete_resource_tuple(ResourceTuple = {_,_}) ->
    rd_core:delete_resource_tuple(ResourceTuple).

%%------------------------------------------------------------------------------
%% @doc Remove a target type and all associated resources.
%% @end
%%------------------------------------------------------------------------------
-spec delete_target_resource_type(resource_type()) -> true.
delete_target_resource_type(Type) ->
    rd_core:delete_target_resource_type(Type).

%%------------------------------------------------------------------------------
%% @doc Remove a local resource. The resource will no longer be available for
%%      other nodes to discover once this call returns.
%% @end
%%------------------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> ok | {error, local_resource_not_found, resource_tuple()}.
delete_local_resource_tuple(LocalResourceTuple) ->
    rd_core:delete_local_resource_tuple(LocalResourceTuple).

%%--------------------------------------------------------------------
%% @doc
%% Delete callback modules
%% @end
%%--------------------------------------------------------------------
-spec delete_callback_modules([atom()]) -> ok.
delete_callback_modules([H|_] = Modules) when is_atom(H) ->
    [rd_core:delete_callback_module(Module) || Module <- Modules],
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Delete callback module
%% @end
%%--------------------------------------------------------------------
-spec delete_callback_module(atom()) -> ok.
delete_callback_module(Module) when is_atom(Module) ->
    delete_callback_modules([Module]).

%%------------------------------------------------------------------------------
%% @doc Gets the number of resource types locally cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_num_resource_types() -> integer().
get_num_resource_types() ->
    rd_core:get_num_resource_types().

%%------------------------------------------------------------------------------
%% @doc Counts the cached instances of a particular resource type.
%% @end
%%------------------------------------------------------------------------------
-spec get_num_resource(resource_type()) -> integer().
get_num_resource(Type) ->
    rd_core:get_num_resource(Type).

%%------------------------------------------------------------------------------
%% @doc Contacts resource discoveries initial contact node.
%%
%% The initial contact node is specified in configuration with:
%% <code>
%%   {contact_nodes, [NodeName]}
%% </code>
%% The config can be overridden by specifying a contact node at the command line
%% like so:
%% <code>
%%  -contact_node foo@bar.com
%% </code>
%%
%% @spec contact_nodes(Timeout) -> ok | {error, bad_contact_node} | {error, no_contact_node}
%% where
%%  Timeout = Milliseconds::integer()
%% @end
%%------------------------------------------------------------------------------
contact_nodes(Timeout) ->
   {ok, ContactNodes} =
	case lists:keysearch(contact_node, 1, init:get_arguments()) of
	    {value, {contact_node, [I_ContactNode]}} ->
		application:set_env(resource_discovery, contact_nodes, [I_ContactNode]),
		{ok, [list_to_atom(I_ContactNode)]};
	    _ -> rd_util:get_env(contact_nodes, [node()])
	end,
    ping_contact_nodes(ContactNodes, Timeout).

%% @spec contact_nodes() -> pong | pang | no_contact_node
%% @equiv contact_nodes(10000)
contact_nodes() ->
    contact_nodes(10000).

ping_contact_nodes([], _Timeout) ->
    error_logger:info_msg("No contact node specified. Potentially running in a standalone node", []),
    {error, no_contact_node};
ping_contact_nodes(Nodes, Timeout) ->
    Reply = rd_util:do_until(fun(Node) ->
			     case rd_util:sync_ping(Node, Timeout) of
				 pong -> true;
				 pang ->
				     error_logger:info_msg("ping contact node at ~p failed", [Node]),
				     false
			     end
		     end,
		     Nodes),
    case Reply of
	false -> {error, bad_contact_node};
	true -> ok
    end.

%%------------------------------------------------------------------------------
%% @doc Execute an rpc on a cached resource.  If the result of the rpc is {badrpc, reason} the
%%      resource is deleted and the next resource is tried, else the result is
%%      returned to the user.
%% <pre>
%% Varibles:
%%  Type - The resource type to get from resource discovery.
%% </pre>
%% @end
%%------------------------------------------------------------------------------
-spec rpc_call(resource_type(), atom(), atom(), [term()], timeout()) -> term() | {error, not_found}.
rpc_call(Type, Module, Function, Args, Timeout) ->
    case get_resource(Type) of
	{ok, Resource} ->
	    %%error_logger:info_msg("got a resource ~p", [Resource]),
	    case rpc:call(Resource, Module, Function, Args, Timeout) of
		{badrpc, Reason} ->
		    error_logger:info_msg("got a badrpc ~p", [Reason]),
		    delete_resource_tuple({Type, Resource}),
		    rpc_call(Type, Module, Function, Args, Timeout);
		Reply ->
		    error_logger:info_msg("result of rpc was ~p", [Reply]),
		    Reply
	    end;
        {error, not_found} -> {error, not_found}
    end.

-spec rpc_call(resource_type(), atom(), atom(), [term()]) -> term() | {error, no_resources}.
rpc_call(Type, Module, Function, Args) ->
    rpc_call(Type, Module, Function, Args, 60000).

%%------------------------------------------------------------------------------
%% @doc Execute an rpc on a cached resource.  Any bad nodes are deleted.
%%      resource is deleted and the next resource is tried, else the result is
%%      returned to the user.
%% @end
%%------------------------------------------------------------------------------
-spec rpc_multicall(resource_type(), atom(), atom(), [term()], timeout()) -> {term(), [node()]} | {error, no_resources}.
rpc_multicall(Type, Module, Function, Args, Timeout) ->
    case get_resources(Type) of
        [] -> {error, no_resources};
	Resources ->
	    %%error_logger:info_msg("got resources ~p", [Resources]),
	    {Resl, BadNodes} = rpc:multicall(Resources, Module, Function, Args, Timeout),
	    [delete_resource_tuple({Type, BadNode}) || BadNode <- BadNodes],
	    {Resl, BadNodes}
    end.

-spec rpc_multicall(resource_type(), atom(), atom(), [term()]) -> {term(), [node()]} | {error, no_resources}.
rpc_multicall(Type, Module, Function, Args) ->
    rpc_multicall(Type, Module, Function, Args, 60000).
