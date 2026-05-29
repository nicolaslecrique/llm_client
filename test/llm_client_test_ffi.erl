-module(llm_client_test_ffi).
-export([
    reset_stream_deltas/0,
    record_stream_delta/1,
    stream_delta_count/0
]).

reset_stream_deltas() ->
    put(llm_client_stream_delta_count, 0),
    nil.

record_stream_delta(_Delta) ->
    put(llm_client_stream_delta_count, stream_delta_count() + 1),
    nil.

stream_delta_count() ->
    case get(llm_client_stream_delta_count) of
        undefined -> 0;
        Count -> Count
    end.
