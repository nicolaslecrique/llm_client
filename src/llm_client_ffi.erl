-module(llm_client_ffi).
-compile({no_auto_import, [error/3]}).
-export([succeed/1, map/2, run/2, await/1, generate_text/1, stream_text/2]).

succeed(Value) ->
    fun() -> Value end.

map(Call, Mapper) ->
    fun() -> Mapper(await(Call)) end.

run(Call, Callback) ->
    Callback(await(Call)),
    nil.

await(Call) when is_function(Call, 0) ->
    Call();
await(Value) ->
    Value.

generate_text(Request) ->
    fun() ->
        case ollama_model(request_model(Request)) of
            {ok, _} -> do_generate_text(Request);
            error ->
                case req_llm_loaded() of
                    true -> do_generate_text(Request);
                    false -> missing_req_llm()
                end
        end
    end.

stream_text(Request, OnText) ->
    fun() ->
        case ollama_model(request_model(Request)) of
            {ok, _} -> do_stream_text(Request, OnText);
            error ->
                case req_llm_loaded() of
                    true -> do_stream_text(Request, OnText);
                    false -> {error, error(<<"req_llm is not available on the BEAM code path">>, <<"missing_dependency">>, <<"">>)}
                end
        end
    end.

req_llm_loaded() ->
    code:ensure_loaded('Elixir.ReqLLM') =:= {module, 'Elixir.ReqLLM'}.

missing_req_llm() ->
    {error, error(<<"req_llm is not available on the BEAM code path">>, <<"missing_dependency">>, <<"">>)}.

do_generate_text(Request) ->
    Model = request_model(Request),
    case ollama_model(Model) of
        {ok, OllamaModel} ->
            ollama_generate_text(OllamaModel, Request);
        error ->
            Input = request_input(Request),
            Options = request_options(Request),
            try 'Elixir.ReqLLM':generate_text(Model, Input, Options) of
                {ok, Response} -> {ok, generate_result(Response)};
                {error, Reason} -> {error, error(<<"LLM generation failed">>, <<"provider_error">>, inspect(Reason))}
            catch
                Class:Reason ->
                    {error, error(<<"LLM generation crashed">>, atom_to_binary(Class), inspect(Reason))}
            end
    end.

do_stream_text(Request, OnText) ->
    Model = request_model(Request),
    case ollama_model(Model) of
        {ok, OllamaModel} ->
            ollama_stream_text(OllamaModel, Request, OnText);
        error ->
            Input = request_input(Request),
            Options = request_options(Request),
            try 'Elixir.ReqLLM':stream_text(Model, Input, Options) of
                {ok, Response} ->
                    Tokens = 'Elixir.ReqLLM.StreamResponse':tokens(Response),
                    lists:foreach(fun(Token) -> OnText(Token) end, enum_to_list(Tokens)),
                    {ok, stream_result(Response)};
                {error, Reason} ->
                    {error, error(<<"LLM streaming failed">>, <<"provider_error">>, inspect(Reason))}
            catch
                Class:Reason ->
                    {error, error(<<"LLM streaming crashed">>, atom_to_binary(Class), inspect(Reason))}
            end
    end.

ollama_model(<<"ollama:", Model/binary>>) -> {ok, Model};
ollama_model(_) -> error.

ollama_generate_text(Model, Request) ->
    Payload = ollama_payload(Model, Request, false),
    case ollama_post(Payload) of
        {ok, Body} -> ollama_generate_result(Body, Request);
        {error, Reason} -> {error, error(<<"Ollama generation failed">>, <<"ollama_error">>, inspect(Reason))}
    end.

ollama_stream_text(Model, Request, OnText) ->
    Payload = ollama_payload(Model, Request, true),
    case ollama_post(Payload) of
        {ok, Body} -> ollama_stream_result(Body, OnText, Request);
        {error, Reason} -> {error, error(<<"Ollama streaming failed">>, <<"ollama_error">>, inspect(Reason))}
    end.

ollama_post(Payload) ->
    application:ensure_all_started(inets),
    Body = iolist_to_binary(json:encode(Payload)),
    Request = {
        "http://127.0.0.1:11434/api/generate",
        [{"content-type", "application/json"}],
        "application/json",
        Body
    },
    case httpc:request(post, Request, [{timeout, 120000}], [{body_format, binary}]) of
        {ok, {{_, Status, _}, _Headers, ResponseBody}} when Status >= 200, Status < 300 ->
            {ok, ResponseBody};
        {ok, {{_, Status, _}, _Headers, ResponseBody}} ->
            {error, #{status => Status, body => ResponseBody}};
        {error, Reason} ->
            {error, Reason}
    end.

ollama_payload(Model, Request, Stream) ->
    {text_request, _Model, _Prompt, _System, _Messages, Settings, _Tools, Output} = Request,
    Payload0 = #{
        <<"model">> => Model,
        <<"prompt">> => ollama_prompt(Request),
        <<"stream">> => Stream,
        <<"options">> => ollama_options(Settings)
    },
    case ollama_format(Output) of
        none -> Payload0;
        {some, Format} -> Payload0#{<<"format">> => Format}
    end.

ollama_prompt({text_request, _Model, Prompt, System, Messages, _Settings, _Tools, _Output}) ->
    Parts =
        case System of
            {some, Sys} -> [<<"System: ">>, Sys, <<"\n">>];
            none -> []
        end ++
        case Messages of
            [] -> [option_or(Prompt, <<"">>)];
            _ -> ollama_messages(Messages)
        end,
    iolist_to_binary(Parts).

ollama_messages(Messages) ->
    lists:map(fun
        ({system_message, Content}) -> [<<"System: ">>, Content, <<"\n">>];
        ({user_message, Content}) -> [<<"User: ">>, Content, <<"\n">>];
        ({assistant_message, Content}) -> [<<"Assistant: ">>, Content, <<"\n">>];
        ({tool_message, _ToolCallId, Content}) -> [<<"Tool: ">>, Content, <<"\n">>]
    end, Messages).

ollama_options({settings, Temperature, MaxTokens, _MaxSteps, _ProviderOptionsJson}) ->
    maps:from_list(
        ollama_option(<<"temperature">>, Temperature)
        ++ ollama_option(<<"num_predict">>, MaxTokens)
    ).

ollama_option(_Key, none) -> [];
ollama_option(Key, {some, Value}) -> [{Key, Value}].

ollama_format(text_output) -> none;
ollama_format({json_output, _Name, _Description}) -> {some, <<"json">>};
ollama_format({object_output, _SchemaJson, _Name, _Description}) -> {some, <<"json">>};
ollama_format({array_output, _ElementSchemaJson, _Name, _Description}) ->
    {some, <<"json">>};
ollama_format({choice_output, _Options, _Name, _Description}) ->
    {some, <<"json">>}.

ollama_generate_result(Body, Request) ->
    Decoded = json:decode(Body),
    Text = maps:get(<<"response">>, Decoded, <<"">>),
    FinishReason = stringify(maps:get(<<"done_reason">>, Decoded, <<"stop">>)),
    Usage = ollama_usage(Decoded),
    OutputJson = ollama_output_json(Text, Request),
    {ok, {generate_text_result, Text, FinishReason, Usage, OutputJson, <<"[]">>, <<"[]">>, Body}}.

ollama_stream_result(Body, OnText, Request) ->
    Chunks = [json:decode(Line) || Line <- binary:split(Body, <<"\n">>, [global]), Line =/= <<>>],
    TextParts = [maps:get(<<"response">>, Chunk, <<"">>) || Chunk <- Chunks],
    lists:foreach(fun
        (<<>>) -> ok;
        (Text) -> OnText(Text)
    end, TextParts),
    Text = iolist_to_binary(TextParts),
    Final = final_ollama_chunk(Chunks),
    FinishReason = stringify(maps:get(<<"done_reason">>, Final, <<"stop">>)),
    Usage = ollama_usage(Final),
    OutputJson = ollama_output_json(Text, Request),
    {ok, {stream_text_result, Text, FinishReason, Usage, OutputJson, Body}}.

final_ollama_chunk([]) -> #{};
final_ollama_chunk(Chunks) -> lists:last(Chunks).

ollama_usage(Decoded) ->
    Input = maps:get(<<"prompt_eval_count">>, Decoded, 0),
    Output = maps:get(<<"eval_count">>, Decoded, 0),
    {usage, Input, Output, Input + Output}.

ollama_output_json(Text, {text_request, _Model, _Prompt, _System, _Messages, _Settings, _Tools, text_output}) ->
    try json:decode(Text) of
        _ -> Text
    catch
        _:_ -> <<"">>
    end;
ollama_output_json(Text, _Request) ->
    Text.

request_model({text_request, Model, _Prompt, _System, _Messages, _Settings, _Tools, _Output}) ->
    Model.

request_input({text_request, _Model, Prompt, System, Messages, _Settings, _Tools, _Output}) ->
    case Messages of
        [] ->
            case System of
                {some, Sys} -> context([{system, Sys}, {user, option_or(Prompt, <<"">>)}]);
                none -> option_or(Prompt, <<"">>)
            end;
        _ ->
            Prefixed = case System of
                {some, Sys} -> [{system, Sys} | message_pairs(Messages)];
                none -> message_pairs(Messages)
            end,
            context(Prefixed)
    end.

request_options({text_request, _Model, _Prompt, _System, _Messages, Settings, Tools, _Output}) ->
    Options0 = settings_options(Settings),
    case Tools of
        [] -> Options0;
        _ -> [{tools, tool_options(Tools)} | Options0]
    end.

settings_options({settings, Temperature, MaxTokens, MaxSteps, ProviderOptionsJson}) ->
    option_entry(temperature, Temperature)
        ++ option_entry(max_tokens, MaxTokens)
        ++ option_entry(max_steps, MaxSteps)
        ++ provider_options(ProviderOptionsJson).

option_entry(_Key, none) -> [];
option_entry(Key, {some, Value}) -> [{Key, Value}].

provider_options(none) -> [];
provider_options({some, Json}) -> [{provider_options_json, Json}].

tool_options(Tools) ->
    [tool_option(Tool) || Tool <- Tools].

tool_option({no_execute_tool, Name, Description, SchemaJson, Strict}) ->
    [{name, Name}, {description, Description}, {parameter_schema_json, SchemaJson}, {strict, Strict}];
tool_option({execute_tool, Name, Description, SchemaJson, Strict, _Execute}) ->
    [{name, Name}, {description, Description}, {parameter_schema_json, SchemaJson}, {strict, Strict}].

message_pairs(Messages) ->
    [message_pair(Message) || Message <- Messages].

message_pair({system_message, Content}) -> {system, Content};
message_pair({user_message, Content}) -> {user, Content};
message_pair({assistant_message, Content}) -> {assistant, Content};
message_pair({tool_message, ToolCallId, Content}) -> {tool, ToolCallId, Content}.

context(Pairs) ->
    Messages = [context_message(Pair) || Pair <- Pairs],
    'Elixir.ReqLLM.Context':new(Messages).

context_message({system, Content}) -> 'Elixir.ReqLLM.Context':system(Content);
context_message({user, Content}) -> 'Elixir.ReqLLM.Context':user(Content);
context_message({assistant, Content}) -> 'Elixir.ReqLLM.Context':assistant(Content);
context_message({tool, ToolCallId, Content}) ->
    try 'Elixir.ReqLLM.Context':tool(ToolCallId, Content)
    catch _:_ -> 'Elixir.ReqLLM.Context':user(Content)
    end.

generate_result(Response) ->
    Text = response_text(Response),
    FinishReason = response_finish_reason(Response),
    Usage = response_usage(Response),
    {generate_text_result, Text, FinishReason, Usage, <<"">>, <<"[]">>, <<"[]">>, inspect(Response)}.

stream_result(Response) ->
    Text = stream_response_text(Response),
    FinishReason = stream_response_finish_reason(Response),
    Usage = stream_response_usage(Response),
    {stream_text_result, Text, FinishReason, Usage, <<"">>, inspect(Response)}.

response_text(Response) ->
    call_or_default('Elixir.ReqLLM.Response', text, [Response], <<"">>).

response_finish_reason(Response) ->
    stringify(call_or_default('Elixir.ReqLLM.Response', finish_reason, [Response], <<"">>)).

response_usage(Response) ->
    usage(call_or_default('Elixir.ReqLLM.Response', usage, [Response], undefined)).

stream_response_text(Response) ->
    call_or_default('Elixir.ReqLLM.StreamResponse', text, [Response], <<"">>).

stream_response_finish_reason(Response) ->
    stringify(call_or_default('Elixir.ReqLLM.StreamResponse', finish_reason, [Response], <<"">>)).

stream_response_usage(Response) ->
    usage(call_or_default('Elixir.ReqLLM.StreamResponse', usage, [Response], undefined)).

usage(undefined) -> {usage, 0, 0, 0};
usage(#{input_tokens := In, output_tokens := Out, total_tokens := Total}) -> {usage, In, Out, Total};
usage(#{prompt_tokens := In, completion_tokens := Out, total_tokens := Total}) -> {usage, In, Out, Total};
usage(_) -> {usage, 0, 0, 0}.

call_or_default(Module, Function, Args, Default) ->
    case erlang:function_exported(Module, Function, length(Args)) of
        true -> apply(Module, Function, Args);
        false -> Default
    end.

enum_to_list(Value) when is_list(Value) -> Value;
enum_to_list(Value) ->
    try 'Elixir.Enum':to_list(Value)
    catch _:_ -> []
    end.

option_or({some, Value}, _Default) -> Value;
option_or(none, Default) -> Default.

stringify(Value) when is_binary(Value) -> Value;
stringify(Value) when is_atom(Value) -> atom_to_binary(Value);
stringify(Value) -> inspect(Value).

inspect(Value) ->
    try unicode:characters_to_binary(io_lib:format("~0p", [Value]))
    catch _:_ -> <<"">>
    end.

error(Message, Code, Raw) ->
    {llm_error, Message, Code, Raw}.
