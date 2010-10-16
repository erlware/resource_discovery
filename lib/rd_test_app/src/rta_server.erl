%%%-------------------------------------------------------------------
%%% @author Martin Logan <martinjlogan@Macintosh.local>
%%% @copyright (C) 2010, Martin Logan
%%% @doc
%%%  
%%% @end
%%% Created : 14 Oct 2010 by Martin Logan <martinjlogan@Macintosh.local>
%%%-------------------------------------------------------------------
-module(rta_server).

-behaviour(gen_server).

%% API
-export([start_link/0, get_pid/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

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
%% @doc Return the pid for the server.
%% @end
%%--------------------------------------------------------------------
get_pid() ->
    gen_server:call(?SERVER, get_pid).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initiates the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    resource_discovery:add_target_resource_types([pid, node]),
    resource_discovery:add_local_resource_tuples([{pid, self()}, {node, node()}]),
    TT = rd_store:get_target_resource_types(),
    error_logger:info_msg("Target types should be [pid, node] we get ~p~n", [TT]),
    resource_discovery:sync_resources(),
    io:format("here~n"),
    R = resource_discovery:get_resources(pid),
    R2 = resource_discovery:get_resources(node),
    error_logger:info_msg("should get pid and node resource for ~p and ~p" ++
			  "~nand the remote node and process. we get ~p ~p~n",
			  [self(), node(), R, R2]),
    {ok, #state{}, 0}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(get_pid, _From, State) ->
    Reply = {ok, self()},
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(timeout, State) ->
    Self = self(),
    spawn(fun() -> Self ! resource_discovery:rpc_multicall(node, ?MODULE, get_pid, []) end),
    spawn(fun() -> Self ! resource_discovery:rpc_call(node, ?MODULE, get_pid, []) end),
    spawn(fun() -> Self ! resource_discovery:rpc_call(node, ?MODULE, get_pid, []) end),
    {noreply, State};
handle_info({ok, Pid}, State) ->
    Pids = resource_discovery:get_resources(pid),
    error_logger:info_msg("call resp ~p and local pid resources ~p~n",
			  [Pid, Pids]),
    {noreply, State};
handle_info({Resp, BadNodes}, State) ->
    Pids = resource_discovery:get_resources(pid),
    error_logger:info_msg("Multicall resp ~p and local pid resources ~p~n~p~n",
			  [Resp, Pids, BadNodes]),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
