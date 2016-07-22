%%% @author Martin Logan <martinjlogan@erlware.org>
%%% @copyright (C) 2010, Martin Logan
%%% @doc
%%%
%%% @end
%%% Created : 28 Oct 2010 by Martin Logan <martinjlogan@Macintosh.local>
-module(rd_util).

%% API
-export([
	 get_env/2,
	 do_until/2,
	 sync_ping/2,
	 poll_until/3,
     log/2
	]).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Applies a fun to all elements of a list until getting a non false
%%      return value from the passed in fun.
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

log(Msg, Args) ->
    case get_env(debug, false) of
        {ok, true} -> error_logger:info_msg(Msg, Args);
        {ok, false} -> ok
    end.

%% @doc Pings a node and returns only after the net kernal distributes the nodes.
-spec sync_ping(node(), timeout()) -> pang | pong.
sync_ping(Node, Timeout) ->
    log("pinging node: ~p", [Node]),
    case net_adm:ping(Node) of
        pong ->
	    Resp =
		poll_until(fun() ->
				   length(get_remote_nodes(Node)) == length(nodes())
			   end,
			   10, Timeout div 10),
            case Resp of
                true  -> pong;
                false -> pang
            end;
        pang ->
	    pang
    end.

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

%% @doc Get application data but provide a default.
-spec get_env(atom(), term()) -> term().
get_env(Key, Default) ->
    case application:get_env(resource_discovery, Key) of
	{ok, Value} -> {ok, Value};
	undefined   -> {ok, Default}
    end.



%%%===================================================================
%%% Internal functions
%%%===================================================================


get_remote_nodes(Node) ->
    try
	Nodes = rpc:call(Node, erlang, nodes, []),
	log("contact node has ~p", [Nodes]),
	Nodes
    catch
	_C:E ->
	    error_logger:info_msg("failed to connect to contact node ~p", [Node]),
	    throw(E)
    end.

