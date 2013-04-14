-module(esywtu_server).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, start_link/0,
         bind/2, prepare/0, unbind/1, jbind/2]).

-record(server_state, { active, start_time, bind_list }).

-import("deps/erlv8/include/erlv8.hrl").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Port = 8989,
    spawn(
      fun () ->
              {ok, Sock} = gen_tcp:listen(Port, [{active, false}]), 
              loop(Sock)
      end
     ),
    {ok, #server_state{
            active=false, 
            start_time=123, 
            bind_list=[{"/", fun() -> "Hello World" end}]}}.

handle_call(activate, _From, State) ->
    {reply, ok, State#server_state{active=true}};

handle_call({unbind, Path}, _From, State) ->
    NewState = State#server_state{
                  bind_list=do_unbind(Path, State#server_state.bind_list)
                 },
    {reply, ok, NewState};

handle_call({bind, Route}, _From, State) ->
    {Path, Function} = Route,
    NewList = [Route|do_unbind(Path, State#server_state.bind_list)],
    NewState = State#server_state{
                  bind_list=NewList
                 },
    io:format("State: ~p~n", [NewState]),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({web_request, Sender}, State) when State#server_state.active == false ->
    Sender ! io_lib:format("no.", []), 
    {noreply, State};

handle_cast({web_request, "/_", Sender}, State) ->
    Sender ! io_lib:fwrite("~p", [lists:map(fun({Url, Fun}) -> Url end, State#server_state.bind_list)]),
    {noreply, State};

handle_cast({web_request, Path, Sender}, State) ->
    case find_route(Path, State#server_state.bind_list) of
        {ok, Function} ->
            Sender ! Function();
        {error, not_found} ->
            Sender ! <<"Not Found.........">>
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% The Server.

loop(Sock) ->
    {ok, Conn} = gen_tcp:accept(Sock),
    Handler = spawn(fun () -> handle(Conn) end),
    gen_tcp:controlling_process(Conn, Handler),
    loop(Sock).

handle(Conn) ->
    case read_and_parse_headers(Conn) of
        {ok, [Method, Path, Type], Headers} ->
            gen_server:cast(?MODULE, {web_request, Path, self()}),
            receive Part -> ok end,
            
            B = iolist_to_binary(Part),
            Response = iolist_to_binary(
                         io_lib:fwrite(
                           "HTTP/1.0 200 OK\nContent-Type: text/html\nContent-Length: ~p\n\n~s",
                           [size(B), B]));
        Else ->
            B = iolist_to_binary(io_lib:fwrite("Issue: ~p", [Else])),
            Response = iolist_to_binary(
                         io_lib:fwrite(
                           "HTTP/1.0 500 OK\nContent-Type: text/html\nContent-Length: ~p\n\n~s",
                           [size(B), B]))
    end,
    
    gen_tcp:send(Conn, Response),
    gen_tcp:close(Conn).

%%% Find route.

find_route(Search, [Route|Rest]) ->
    {Path, Function} = Route,
    case Path of
        Search ->
            {ok, Function};
        _ ->
            find_route(Search, Rest)
    end;
                
find_route(Search, []) ->
    {error, not_found}.

%%% bind route

bind(Url, Fun) ->
    gen_server:call(?MODULE, {bind, {Url, Fun}}).

jbind(Url, Fun) ->
    gen_server:call(?MODULE, {bind, {Url, fun() -> jiffy:encode(Fun()) end}}).

unbind(Path) ->
    gen_server:call(?MODULE, {unbind, Path}).

do_unbind(Url, List) ->
    do_unbind(Url, List, []).

do_unbind(Url, [Head|Rest], Accum) ->
    {Path, Function} = Head,
    case Path of
        Url ->
            do_unbind(Url, Rest, Accum);
        Other ->
            do_unbind(Url, Rest, [Head|Accum])
    end;

do_unbind(Url, [], Accum) ->
    Accum.

prepare() ->
    ?MODULE:start_link(),
    gen_server:call(?MODULE, activate).

%%% Parse headers.

read_and_parse_headers(Conn) ->
    Raw = lists:flatten(lists:reverse(read_and_parse_headers(Conn, []))),
    Parsed = parse_raw_header(string:tokens(Raw, "\r\n"), []),
    case Parsed of
        [] ->
            {error, Parsed};
        _ ->
            [[Request]|Headers] = lists:reverse(Parsed),
            {ok, string:tokens(Request, " "), Headers}
    end.

read_and_parse_headers(Conn, ["\n"|["\r"|["\n"|["\r"|Rest]]]]) ->
    Rest;

read_and_parse_headers(Conn, Accum) ->
    case gen_tcp:recv(Conn, 1) of
        {ok, Data} ->
            read_and_parse_headers(Conn, [Data|Accum]);
        {error, Reason} ->
            Accum
    end.

parse_raw_header([Head|Rest], Accum) ->
    parse_raw_header(Rest, [string:tokens(Head, ":")|Accum]);

parse_raw_header([], Accum) ->
    Accum.
