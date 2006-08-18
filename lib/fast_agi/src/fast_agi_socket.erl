%%%
%%% This library is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU Lesser General Public
%%% License as published by the Free Software Foundation; either
%%% version 2.1 of the License, or (at your option) any later version.
%%%
%%% This library is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public
%%% License along with this library; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA

%%%-------------------------------------------------------------------
%%% File    : fast_agi_socket.erl
%%% Created : 30 Mar 2006 
%%% @author Anders Nygren <anders.nygren@gmail.com>
%%% @copyright 2006 Anders Nygren
%%% @version {@vsn}
%%% @doc Worker process for the fast_agi server.
%%% Listens on the listener port for a connection request. When a
%%% connection is establised it calls fast_agi_server:create/2 to
%%% create a new listener process and the continues handling the
%%% request.
%%% @end
%%%-------------------------------------------------------------------

-module(fast_agi_socket).

-export([start_link/3,
	send/2]).

-export([init/1]).

-include("fast_agi.hrl").

%%-------------------------------------------------------------------
%% API
%%-------------------------------------------------------------------
%% @doc Start the server
start_link(ListenPid, ListenSocket, ListenPort) ->
    proc_lib:spawn_link(?MODULE, init, [{ListenPid, 
					 ListenSocket, 
					 ListenPort}]).

%% @doc Send a pdu to the client.
send(C,Pack) ->
    io:format("sending ~p~n",[Pack]),
    gen_tcp:send(C#connection.sock,Pack),
    check_result(C).

%%-------------------------------------------------------------------
%% Callbacks
%%-------------------------------------------------------------------
%% @private
init({Listen_pid, Listen_socket, ListenPort}) ->
    case catch gen_tcp:accept(Listen_socket) of
	{ok, Socket} ->
	    %% Send the cast message to the listener process to 
	    %% create a new acceptor
	    fast_agi_server:create(Listen_pid, self()),
	    {ok, {Addr, Port}} = inet:peername(Socket),
            C = #connection{sock = Socket,
			    port = ListenPort,
			    peer_addr = Addr,
			    peer_port = Port},
	    request(C, []);
	Else ->
	    error_logger:error_report([{application, fast_agi},
				       "Accept failed error",
				       io_lib:format("~p",[Else])]),
	    exit({error, accept_failed})
    end.

%%-------------------------------------------------------------------
%% Internal functions
%%-------------------------------------------------------------------
check_result(C) ->
    {ok,R}=gen_tcp:recv(C#connection.sock, 0, 30000),
    io:format("result ~p~n",[R]),
    Res=string:sub_word(R,1,$\n),
    [list_to_integer(string:sub_word(Res,1)),
     list_to_integer(string:sub_word(string:sub_word(Res,2),2,$=)),
     string:sub_word(Res,3)].

request(C, Req) ->
    case gen_tcp:recv(C#connection.sock, 0, 30000) of
	{ok,Some} ->
	    case string:str(Some,"\n\n") of
		0 ->
		    request(C,Req++Some);
		_N ->
		    RPars=parse_req(Req++Some),
		    handle_req(C,RPars)
	    end;
	error ->
	    io:format("Got error~n",[])
    end.

parse_req(Req) ->
    [parse_line(L)||L<-string:tokens(Req,"\n")].

parse_line(L) ->
    Par=string:sub_word(L,1,$:),
    Val=string:strip(string:sub_word(L,2,$:),both),
    {list_to_atom(Par),Val}.

handle_req(C,RPars) ->
    io:format("handle_req: ~p~n",[RPars]),
    {Mod,Fun}=get_script(RPars),
    case catch Mod:Fun(RPars,C) of
	Res ->
	    io:format("RESULT ~p~n",[Res]),
	    gen_tcp:close(C#connection.sock,read_write),
	    Res
    end.
	
get_script(Req) ->
    Script=fast_agi:get_var("agi_network_script",Req),
    list_to_tuple([list_to_atom(T) || T<-string:tokens(Script,"/")]).
