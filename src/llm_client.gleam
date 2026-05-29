import gleam/option.{type Option, None, Some}

/// A target-specific async call.
///
/// On JavaScript this is backed by a `Promise`. On BEAM it is backed by a
/// zero-arity function, so it can be awaited synchronously.
pub type Call(value)

/// Chat messages accepted by `generate_text` and `stream_text`.
pub type Message {
  SystemMessage(content: String)
  UserMessage(content: String)
  AssistantMessage(content: String)
  ToolMessage(tool_call_id: String, content: String)
}

/// Structured output configuration, matching the AI SDK `Output` modes.
///
/// JSON schemas are passed as strings so the API stays portable across Gleam's
/// JavaScript and BEAM targets.
pub type Output {
  TextOutput
  JsonOutput(name: Option(String), description: Option(String))
  ObjectOutput(
    schema_json: String,
    name: Option(String),
    description: Option(String),
  )
  ArrayOutput(
    element_schema_json: String,
    name: Option(String),
    description: Option(String),
  )
  ChoiceOutput(
    options: List(String),
    name: Option(String),
    description: Option(String),
  )
}

/// A callable tool.
///
/// `input_schema_json` must be a JSON Schema object. `execute` receives the
/// model's tool input encoded as JSON and returns the tool result encoded as
/// JSON. If you only want the model to emit tool calls, use `NoExecuteTool`.
pub type Tool {
  ExecuteTool(
    name: String,
    description: String,
    input_schema_json: String,
    strict: Bool,
    execute: fn(String) -> String,
  )
  NoExecuteTool(
    name: String,
    description: String,
    input_schema_json: String,
    strict: Bool,
  )
}

pub type Settings {
  Settings(
    temperature: Option(Float),
    max_tokens: Option(Int),
    max_steps: Option(Int),
    provider_options_json: Option(String),
  )
}

pub type TextRequest {
  TextRequest(
    model: String,
    prompt: Option(String),
    system: Option(String),
    messages: List(Message),
    settings: Settings,
    tools: List(Tool),
    output: Output,
  )
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int, total_tokens: Int)
}

pub type GenerateTextResult {
  GenerateTextResult(
    text: String,
    finish_reason: String,
    usage: Usage,
    output_json: String,
    tool_calls_json: String,
    tool_results_json: String,
    raw_json: String,
  )
}

pub type StreamTextResult {
  StreamTextResult(
    text: String,
    finish_reason: String,
    usage: Usage,
    output_json: String,
    raw_json: String,
  )
}

pub type LlmError {
  LlmError(message: String, code: String, raw: String)
}

pub fn default_settings() -> Settings {
  Settings(
    temperature: None,
    max_tokens: None,
    max_steps: None,
    provider_options_json: None,
  )
}

pub fn prompt(model model: String, prompt prompt: String) -> TextRequest {
  TextRequest(
    model: model,
    prompt: Some(prompt),
    system: None,
    messages: [],
    settings: default_settings(),
    tools: [],
    output: TextOutput,
  )
}

pub fn with_system(request: TextRequest, system: String) -> TextRequest {
  TextRequest(..request, system: Some(system))
}

pub fn with_messages(
  request: TextRequest,
  messages: List(Message),
) -> TextRequest {
  TextRequest(..request, messages: messages)
}

pub fn with_settings(request: TextRequest, settings: Settings) -> TextRequest {
  TextRequest(..request, settings: settings)
}

pub fn with_tools(request: TextRequest, tools: List(Tool)) -> TextRequest {
  TextRequest(..request, tools: tools)
}

pub fn with_output(request: TextRequest, output: Output) -> TextRequest {
  TextRequest(..request, output: output)
}

pub fn with_temperature(settings: Settings, temperature: Float) -> Settings {
  Settings(..settings, temperature: Some(temperature))
}

pub fn with_max_tokens(settings: Settings, max_tokens: Int) -> Settings {
  Settings(..settings, max_tokens: Some(max_tokens))
}

pub fn with_max_steps(settings: Settings, max_steps: Int) -> Settings {
  Settings(..settings, max_steps: Some(max_steps))
}

pub fn with_provider_options_json(
  settings: Settings,
  provider_options_json: String,
) -> Settings {
  Settings(..settings, provider_options_json: Some(provider_options_json))
}

/// Generate text from an LLM provider.
///
/// JavaScript wraps Vercel AI SDK Core's `generateText`; BEAM wraps
/// `ReqLLM.generate_text/3` when the `req_llm` application is available.
pub fn generate_text(
  request: TextRequest,
) -> Call(Result(GenerateTextResult, LlmError)) {
  generate_text_ffi(request)
}

/// Stream text from an LLM provider.
///
/// `on_text` is called for each text delta. The returned call completes with
/// the final collected stream metadata.
pub fn stream_text(
  request: TextRequest,
  on_text: fn(String) -> Nil,
) -> Call(Result(StreamTextResult, LlmError)) {
  stream_text_ffi(request, on_text)
}

pub fn map(call: Call(a), mapper: fn(a) -> b) -> Call(b) {
  map_ffi(call, mapper)
}

pub fn run(call: Call(a), callback: fn(a) -> Nil) -> Nil {
  run_ffi(call, callback)
}

/// Await a call.
///
/// This is synchronous on BEAM. On JavaScript it returns a promise-like value to
/// JavaScript callers; Gleam code compiled to JavaScript should usually prefer
/// `run`.
pub fn await(call: Call(a)) -> a {
  await_ffi(call)
}

@external(erlang, "llm_client_ffi", "succeed")
@external(javascript, "./llm_client_ffi.mjs", "succeed")
pub fn succeed(value: a) -> Call(a)

@external(erlang, "llm_client_ffi", "map")
@external(javascript, "./llm_client_ffi.mjs", "map")
fn map_ffi(call: Call(a), mapper: fn(a) -> b) -> Call(b)

@external(erlang, "llm_client_ffi", "run")
@external(javascript, "./llm_client_ffi.mjs", "run")
fn run_ffi(call: Call(a), callback: fn(a) -> Nil) -> Nil

@external(erlang, "llm_client_ffi", "await")
@external(javascript, "./llm_client_ffi.mjs", "awaitCall")
fn await_ffi(call: Call(a)) -> a

@external(erlang, "llm_client_ffi", "generate_text")
@external(javascript, "./llm_client_ffi.mjs", "generateText")
fn generate_text_ffi(
  request: TextRequest,
) -> Call(Result(GenerateTextResult, LlmError))

@external(erlang, "llm_client_ffi", "stream_text")
@external(javascript, "./llm_client_ffi.mjs", "streamText")
fn stream_text_ffi(
  request: TextRequest,
  on_text: fn(String) -> Nil,
) -> Call(Result(StreamTextResult, LlmError))
