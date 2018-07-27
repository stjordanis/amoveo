-module(testnet_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->

    application:start(inets),
    inets:start(),
    make_block_folders(),
    sync:cron(),
    push_block:cron(),

    io:fwrite("starting testnet node"),

    testnet_sup:start_link().


stop(_State) ->
    ok.

make_block_folders() ->
    mbf(0).
mbf(256) -> ok;
mbf(N) ->
    Code = blocks,
    H = to_hex(<<N>>),
    Dir = file_dir(Code),
    os:cmd("mkdir "++Dir++H),
    mbf(N+1).
file_dir(blocks) -> "blocks/".

to_hex(<<>>) ->  [];
to_hex(<<A:4, B/bitstring>>) ->
    if
	A < 10 -> [(A+48)|to_hex(B)];
	true -> [(A+87)|to_hex(B)]
    end.
    
