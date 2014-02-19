%% @author Marc Worrell
%% @copyright 2013-2014 Marc Worrell

%% Copyright 2013-2014 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(filecache).

-export([
    insert/2, 
    insert_file/2,
    insert_tmpfile/2,
    insert_stream/1,
    append_stream/2,
    finish_stream/1,
    lookup/1, 
    lookup_file/1, 
    delete/1,

    stats/0,

    data_dir/0,
    journal_dir/0,
    checksum/1
    ]).

-define(BLOCK_SIZE, 65536).


%%% API

insert(Key, Bin) when is_binary(Bin) ->
    insert_1(Key, {data, Bin}).

insert_file(Key, FilePath) ->
    insert_1(Key, {file, FilePath}).

insert_tmpfile(Key, FilePath) ->
    insert_1(Key, {tmpfile, FilePath}).

insert_stream(Key) ->
    insert_1(Key, {stream_start, self()}).

append_stream(Pid, Bin) ->
    filecache_entry:append_stream(Pid, Bin).

finish_stream(Pid) ->
    filecache_entry:finish_stream(Pid).

-spec lookup(term()) -> {ok, {file, integer(), string()}} | {ok, {stream, function()}} | {error, term()}.
lookup(Key) ->
    filecache_event:lookup(Key),
    case filecache_store:lookup(Key) of
        {ok, Pid} ->
            filecache_entry:fetch(Pid);
        {error, _} = Error ->
            Error
    end.

lookup_file(Key) ->
    filecache_event:lookup(Key),
    case filecache_store:lookup(Key) of
        {ok, Pid} ->
            try
                filecache_entry:fetch_file(Pid)
            catch
                exit:{noproc, _} ->
                    {error, not_found}
            end;
        {error, _} = Error ->
            Error
    end.

delete(Key) ->
    case filecache_store:lookup(Key) of
        {ok, Pid} ->
            filecache_entry:delete(Pid);
        {error, _Reason} ->
            ok
    end.

stats() ->
    filecache_entry_manager:stats().

%%% Support functions

insert_1(Key, What) ->
    insert_or_error(filecache_store:lookup(Key), Key, What).

insert_or_error({ok, Pid}, _Key, _What) ->
    {error, {already_started, Pid}};
insert_or_error({error, not_found}, Key, What) ->
    case filecache_entry_manager:insert(Key) of
        {ok, Pid} ->
            filecache_entry:store(Pid, What),
            {ok, Pid};
        {error, _} = Error ->
            Error
    end.


%% @doc Return the directory for the storage of the cached files
-spec data_dir() -> file:filename().
data_dir() ->
    case application:get_env(data_dir) of
        undefined -> filename:join([priv_dir(), "data"]);
        DataDir -> DataDir
    end.

%% @doc Return the directory for the storage of the log/journal files
-spec journal_dir() -> file:filename().
journal_dir() ->
    case application:get_env(journal_dir) of
        undefined -> filename:join([priv_dir(), "journal"]);
        DataDir -> DataDir
    end.

priv_dir() ->
    case code:priv_dir(?MODULE) of
        {error, bad_name} -> "priv";
        PrivDir -> PrivDir
    end.

-spec checksum(file:filename()) -> binary().
checksum(Filename) ->
    Ctx = crypto:hash_init(sha),
    {ok, FD} = file:open(Filename, [read,binary]),
    Ctx1 = checksum1(Ctx, FD),
    file:close(FD),
    crypto:hash_final(Ctx1).

checksum1(Ctx, FD) ->
    case file:read(FD, ?BLOCK_SIZE) of
        eof ->
            Ctx;
        {ok, Data} ->
            checksum1(crypto:hash_update(Ctx, Data), FD)
    end.
