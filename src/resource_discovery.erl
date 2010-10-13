%%%-------------------------------------------------------------------
%%% File    : resource_discovery.erl
%%% Author  : Martin J. Logan <martinjlogan@erlware.org>
%%% @doc 
%%%
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
         start/2
        ]).

% Add
-export([
         add_local_resource_tuples/1,
         add_target_resource_types/1,
         add_callback_modules/1
        ]).

% Get
-export([
         get_resource/1, 
         get_resource/2, 
         get_all_resources/1, 
         get_num_resource/1, 
         get_resource_types/0,
         get_num_resource_types/0,
         get_contact_nodes/0
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_resource_type/1,
         delete_resource/2, 
         delete_resource/1 
        ]).

% Other
-export([
         trade_resources/0,
         contact_nodes/0,
         rpc_call/4
        ]).

-include("resource_discovery.hrl").
-include("macros.hrl").

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(RD, rd_core).

%%====================================================================
%% External functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Starts the resource discovery application.
%% @spec start(Type, StartArgs) -> {ok, Pid} | {ok, Pid, State} | {error, Reason}
%% @end
%%--------------------------------------------------------------------
start(_Type, StartArgs) ->
    case rd_sup:start_link(StartArgs) of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc inform an rd_core server of local resources and target types.
%%      This will prompt the remote servers to asyncronously send
%%      back remote resource information.
%% @end
%%--------------------------------------------------------------------
-spec trade_resources() -> ok.
trade_resources() ->
    rd_core:trade_resources().

%%------------------------------------------------------------------------------
%% @doc Adds to the list of target types. Target types are the types
%%      of resources that this instance of resource_discovery will cache following
%%      a notification of such a resource from a resource_discovery instance.
%%      This includes the local instance.
%% @end
%%------------------------------------------------------------------------------
-spec add_target_resource_types([resource_type()]) -> no_return().
add_target_resource_types(TargetTypes) -> 
    rd_store:store_target_resource_types(TargetTypes).

%%------------------------------------------------------------------------------
%% @doc Adds to the list of local resource tuples. 
%% @end
%%------------------------------------------------------------------------------
-spec add_local_resource_tuples([resource_tuple()]) -> no_return().
add_local_resource_tuples(LocalResourceTuples) -> 
    rd_store:store_local_resources(LocalResourceTuples).

%%------------------------------------------------------------------------------
%% @doc Add a callback module or modules to the list of callbacks to be
%%      called upon new resources entering the system.
%% @end
%%------------------------------------------------------------------------------
-spec add_callback_modules([atom()]) -> no_return().
add_callback_modules(Modules) ->
    rd_store:store_callback_modules(Modules).

%%------------------------------------------------------------------------------
%% @doc Returns a cached resource.
%% @end
%%------------------------------------------------------------------------------
-spec get_resource(resource_type()) -> {ok, resource()} | {error, no_resources}.
get_resource(Type) ->
    gen_server:call(?RD, {get_resource, Type}). 

%%------------------------------------------------------------------------------
%% @doc Replies with the cached resource at the index specified. If for example we had
%%      a list of resources that looked like {R1, R2, R3} and index 2 was
%%      requested the user would receive R2.
%% @spec (resource_type(), Index::integer()) -> {ok, resource()} | {error, no_resources}
%% @end
%%------------------------------------------------------------------------------
-spec get_resource(resource_type(), pos_integer()) -> {ok, resource()} | {error, no_resources}.
get_resource(Type, Index) ->
    gen_server:call(?RD, {get_resource, Type, Index}). 

%%------------------------------------------------------------------------------
%% @doc Returns ALL cached resources for a particular type.
%% @end
%%------------------------------------------------------------------------------
-spec get_all_resources(resource_type()) -> [resource()].
get_all_resources(Type) ->
    gen_server:call(?RD, {get_all_resources, Type}). 

%%------------------------------------------------------------------------------
%% @doc Removes a cached resource from the resource pool. Only returns after the
%%      resource has been deleted.
%% @end
%%------------------------------------------------------------------------------
-spec delete_resource(resource_type(), resource()) -> ok.
delete_resource(Type, Instance) ->
    delete_resource({Type, Instance}).

%% @equiv delete_resource(resource_type(), resource())
-spec delete_resource(resource_tuple()) -> ok.
delete_resource(ResourceTuple = {_,_}) ->
    gen_server:call(?RD, {delete_resource, ResourceTuple}).

%%------------------------------------------------------------------------------
%% @doc Counts the cached instances of a particular resource type.
%% @end
%%------------------------------------------------------------------------------
-spec get_num_resource(resource_type()) -> integer().
get_num_resource(Type) ->
    gen_server:call(?RD, {get_num_resource, Type}). 

%%------------------------------------------------------------------------------
%% @doc Remove a target type and all associated resources. 
%% @end
%%------------------------------------------------------------------------------
-spec delete_target_resource_type(resource_type()) -> true.
delete_target_resource_type(Type) ->
    rd_store:delete_target_resource_type(Type).

%%------------------------------------------------------------------------------
%% @doc Remove a local resource. The resource will no longer be available for
%%      other nodes to discover once this call returns.
%% @end
%%------------------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> no_return().
delete_local_resource_tuple(LocalResourceTuple) ->
    rd_store:delete_local_resource_tuple(LocalResourceTuple).

%%------------------------------------------------------------------------------
%% @doc Gets a list of the types that have resources that have been cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_resource_types() -> [resource_type()].
get_resource_types() ->
    gen_server:call(?RD, get_resource_types). 

%%------------------------------------------------------------------------------
%% @doc Gets the number of resource types locally cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_num_resource_types() -> integer().
get_num_resource_types() ->
    gen_server:call(?RD, get_num_resource_types). 
					    
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
		gas:set_env(resource_discovery, contact_nodes, [I_ContactNode]),
		{ok, [list_to_atom(I_ContactNode)]};
	    _ ->
		gas:get_env(resource_discovery, contact_nodes, [])
	end,
    ping_contact_nodes(ContactNodes, Timeout).

%% @spec contact_nodes() -> pong | pang | no_contact_node
%% @equiv contact_nodes(10000)
contact_nodes() ->
    contact_nodes(10000).

ping_contact_nodes([], _Timeout) ->
    ?INFO_MSG("No contact node specified. Potentially running in a standalone node~n", []),
    {error, no_contact_node};
ping_contact_nodes(Nodes, Timeout) ->
    fs_lists:do_until(fun(Node) ->
			      case fs_net:sync_ping(Node, Timeout) of
				  pong ->
				      ok;
				  pang ->
				      ?INFO_MSG("ping contact node at ~p failed~n", [Node]), 
				      {error, bad_contact_node}
			      end
		      end,
		      ok,
		      Nodes).

%%------------------------------------------------------------------------------
%% @doc Get the contact node for the application.
%% @spec get_contact_nodes() -> {ok, Value} | undefined
%% where
%%  Value = node() | [node()]
%% @end
%%------------------------------------------------------------------------------
get_contact_nodes() ->
    gas:get_env(resource_discovery, contact_nodes).
    
%%------------------------------------------------------------------------------
%% @doc Execute an rpc on a cached resource.  If the result of the rpc is {badrpc, reason} the 
%%      resource is deleted and the next resource is tried, else the result is 
%%      returned to the user.
%% <pre>
%% Varibles:
%%  Type - The resource type to get from resource discovery.
%% </pre>
%% @spec (Type, Module, Function, Args) -> RPCResult | {error, no_resources}
%% @end
%%------------------------------------------------------------------------------
-spec rpc_call(resource_type(), atom(), atom(), [term()]) -> term() | {error, no_resources}.
rpc_call(Type, Module, Function, Args) ->
    case get_resource(Type) of
	{ok, Resource} -> 
	    io:format("got a resource ~p~n", [Resource]),
	    case rpc:call(Resource, Module, Function, Args) of
		{badrpc, Reason} ->
		    io:format("got a badrpc ~p~n", [Reason]),
		    delete_resource(Type, Resource),
		    rpc_call(Type, Module, Function, Args);
		Reply ->
		    io:format("result of rpc was ~p~n", [Reply]),
		    Reply
	    end;
        {error, no_resources} -> 
	    {error, no_resources}
    end.


