%%%-------------------------------------------------------------------
%%% File    : rd_heartbeat.erl
%%% Author  : Martin J. Logan 
%%% @doc This does an inform nodes at a specified time interval.
%%% @end
%%%-------------------------------------------------------------------
-module(rd_heartbeat).

-behaviour(gen_server).

%% External exports
-export([ start_link/1, start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {frequency}).

%%====================================================================
%% External functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Starts the server
%% <pre> 
%% Expects:
%%  Frequency - The frequency of heartbeats in milliseconds.
%% </pre>
%% @end
%%--------------------------------------------------------------------
-spec start_link(non_neg_integer()) -> {ok, pid()}.
start_link(Frequency) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Frequency], []).

%% @equiv start_link(0) 
start_link() ->
    %% The default value is 0 which indicates no heartbeating. 
    Frequency = rd_util:get_env(heartbeat_frequency, 0),
    start_link(Frequency).

%%====================================================================
%% Server functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%--------------------------------------------------------------------
init([Frequency]) ->
    error_logger:info_msg("~n", []),
    ok = resource_discovery:contact_nodes(),
    {ok, #state{frequency = Frequency}, Frequency}.

%%--------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_info(timeout, State = #state{frequency = 0}) ->
    {stop, normal, State};
handle_info(timeout, State = #state{frequency = Frequency}) ->
    resource_discovery:contact_nodes(),
    resource_discovery:trade_resources(),
    %% Wait for approximately the frequency with a random factor.
    {noreply, State, random:uniform(Frequency div 2) + (Frequency div 2) + Frequency div 3}.

%%--------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%%--------------------------------------------------------------------
terminate(Reason, _State) ->
    error_logger:info_msg("stoppping resource discovery hearbeat ~p~n", [Reason]),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

