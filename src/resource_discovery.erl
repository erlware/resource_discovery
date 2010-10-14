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
         get_num_resource_types/0,
         get_contact_nodes/0
        ]).

% Delete
-export([
         delete_local_resource_tuple/1,
         delete_target_resource_type/1,
         delete_resource_tuple/1 
        ]).

% Other
-export([
         trade_resources/0,
         sync_resources/1,
         sync_resources/0,
         contact_nodes/0,
         rpc_call/4
        ]).

-include("resource_discovery.hrl").

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
    % Create the storage for the local parameters; i.e. LocalTypes 
    % and TargetTypes.
    rd_store:new(),
    rd_sup:start_link(StartArgs).

%%--------------------------------------------------------------------
%% @doc inform an rd_core server of local resources and target types.
%%      This will prompt the remote servers to asyncronously send
%%      back remote resource information.
%% @end
%%--------------------------------------------------------------------
-spec trade_resources() -> ok.
trade_resources() ->
    rd_core:trade_resources().

%%-----------------------------------------------------------------------
%% @doc Syncronizes resources between the caller and the node supplied.
%%      Like trade resources but this call blocks.
%% @end
%%-----------------------------------------------------------------------
-spec sync_resources(timeout()) -> ok.
sync_resources(Timeout) ->
    Self = self(),
    Pids = [spawn(fun() ->
			  Self ! {'$sync_resources$', self(), (catch rd_core:sync_resources(Node))}
		  end)
	    || Node <- nodes(known)],
    get_responses(Pids, Timeout).

get_responses([], _Timeout) ->
    ok;
get_responses(Pids, Timeout) ->
    %% XXX TODO fix the timeout by subracting elapsed time.
    %% XXX TODO perhaps use the response.
    receive
	{'$sync_resources$', Pid, _Resp} ->
	    NewPids = lists:delete(Pid, Pids),
	    get_responses(NewPids, Timeout)
    after
	Timeout ->
	    {error, timeout}
    end.
			  
-spec sync_resources() -> ok.
sync_resources() ->
    sync_resources(10000).

%%------------------------------------------------------------------------------
%% @doc Adds to the list of target types. Target types are the types
%%      of resources that this instance of resource_discovery will cache following
%%      a notification of such a resource from a resource_discovery instance.
%%      This includes the local instance.
%% @end
%%------------------------------------------------------------------------------
-spec add_target_resource_types([resource_type()]) -> no_return().
add_target_resource_types([H|_] = TargetTypes) when is_atom(H) -> 
    rd_store:store_target_resource_types(TargetTypes).

-spec add_target_resource_type(resource_type()) -> no_return().
add_target_resource_type(TargetType) when is_atom(TargetType) -> 
    add_target_resource_types([TargetType]).

%%------------------------------------------------------------------------------
%% @doc Adds to the list of local resource tuples. 
%% @end
%%------------------------------------------------------------------------------
-spec add_local_resource_tuples([resource_tuple()]) -> no_return().
add_local_resource_tuples([{T,_}|_] = LocalResourceTuples) when is_atom(T) -> 
    rd_store:store_local_resource_tuples(LocalResourceTuples).

-spec add_local_resource_tuple(resource_tuple()) -> no_return().
add_local_resource_tuple({T,_} = LocalResourceTuple) when is_atom(T) -> 
    add_local_resource_tuples([LocalResourceTuple]).

%%------------------------------------------------------------------------------
%% @doc Add a callback module or modules to the list of callbacks to be
%%      called upon new resources entering the system.
%% @end
%%------------------------------------------------------------------------------
-spec add_callback_modules([atom()]) -> no_return().
add_callback_modules([H|_] = Modules) when is_atom(H) ->
    rd_store:store_callback_modules(Modules).

-spec add_callback_module(atom()) -> no_return().
add_callback_module(Module) when is_atom(Module) ->
    add_callback_modules([Module]).

%%------------------------------------------------------------------------------
%% @doc Replies with the cached resource. Round robins though the resources
%%      cached.
%% @end
%%------------------------------------------------------------------------------
-spec get_resource(resource_type()) -> {ok, resource()} | {error, no_resources}.
get_resource(Type) when is_atom(Type) ->
    rd_core:round_robin_get(Type). 

%%------------------------------------------------------------------------------
%% @doc Returns ALL cached resources for a particular type.
%% @end
%%------------------------------------------------------------------------------
-spec get_resources(resource_type()) -> [resource()].
get_resources(Type) ->
    rd_store:get_resources(Type).

%%------------------------------------------------------------------------------
%% @doc Removes a cached resource from the resource pool. Only returns after the
%%      resource has been deleted.
%% @end
%%------------------------------------------------------------------------------
-spec delete_resource_tuple(resource_tuple()) -> ok.
delete_resource_tuple(ResourceTuple = {_,_}) ->
    rd_store:delete_resource_tuple(ResourceTuple).

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
    rd_core:delete_target_resource_type(Type).

%%------------------------------------------------------------------------------
%% @doc Remove a local resource. The resource will no longer be available for
%%      other nodes to discover once this call returns.
%% @end
%%------------------------------------------------------------------------------
-spec delete_local_resource_tuple(resource_tuple()) -> no_return().
delete_local_resource_tuple(LocalResourceTuple) ->
    rd_core:delete_local_resource_tuple(LocalResourceTuple).

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
    error_logger:info_msg("No contact node specified. Potentially running in a standalone node~n", []),
    {error, no_contact_node};
ping_contact_nodes(Nodes, Timeout) ->
    Reply = do_until(fun(Node) ->
			     case sync_ping(Node, Timeout) of
				 pong ->
				     true;
				 pang ->
				     error_logger:info_msg("ping contact node at ~p failed~n", [Node]), 
				     false
			     end
		     end,
		     Nodes),

    case Reply of
	false ->
	    {error, bad_contact_node};
	true ->
	    ok
    end.
	    

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
		    delete_resource_tuple({Type, Resource}),
		    rpc_call(Type, Module, Function, Args);
		Reply ->
		    io:format("result of rpc was ~p~n", [Reply]),
		    Reply
	    end;
        {error, no_resources} -> 
	    {error, no_resources}
    end.


%%----------------------------------------------------------------------------
%% @private
%% @doc Applies a fun to all elements of a list until getting a non false
%%      return value from the passed in fun.
%% @end
%%----------------------------------------------------------------------------
-spec do_until(term(), list()) -> term() | false.
do_until(_F, []) ->
    false;
do_until(F, [Last]) ->
    F(Last);
do_until(F, [H|T]) ->
    case F(H) of
	false  -> do_until(F, T);
	Return -> Return
    end.
    
%%--------------------------------------------------------------------
%% @private
%% @doc Pings a node and returns only after the net kernal distributes the nodes.
%% This function will return pang after 10 seconds if the Node is not found in nodes()
%%
%% @end
%%--------------------------------------------------------------------
-spec sync_ping(node(), timeout()) -> pang | pong.
sync_ping(Node, Timeout) ->
    case net_adm:ping(Node) of
        pong ->
            case poll_until(fun() -> lists:member(Node, nodes(known)) end, 500, Timeout / 500) of
                true  -> pong;
                false -> pang
            end;
        pang ->
            pang
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc This is a higher order function that allows for Iterations
%%      number of executions of Fun until false is not returned 
%%      from the Fun pausing for PauseMS after each execution.
%% <pre>
%% Variables:
%%  Fun - A fun to execute per iteration.
%%  Iterations - The maximum number of iterations to try getting Reply out of Fun.  
%%  PauseMS - The number of miliseconds to wait inbetween each iteration.
%%  Return - What ever the fun returns.
%% </pre>
%% @end
%%--------------------------------------------------------------------
-spec poll_until(term(), timeout(), timeout()) -> term() | false.
poll_until(Fun, 0, _PauseMS) ->
    Fun();
poll_until(Fun, Iterations, PauseMS) ->
    case Fun() of
        false -> 
            timer:sleep(PauseMS),
            case Iterations of 
                infinity   -> poll_until(Fun, Iterations, PauseMS);
                Iterations -> poll_until(Fun, Iterations - 1, PauseMS)
            end;
        Reply -> 
            Reply
    end.
