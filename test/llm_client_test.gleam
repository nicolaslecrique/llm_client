import gleam/option.{None, Some}
import gleam/string
import gleeunit
import llm_client

pub fn main() {
  gleeunit.main()
}

const local_model = "ollama:tinyllama:1.1b"

pub fn prompt_builder_test() {
  let request = llm_client.prompt(model: "openai:gpt-4o-mini", prompt: "Hello")

  assert request.model == "openai:gpt-4o-mini"
  assert request.prompt == Some("Hello")
  assert request.messages == []
}

pub fn settings_builder_test() {
  let settings =
    llm_client.default_settings()
    |> llm_client.with_temperature(0.2)
    |> llm_client.with_max_tokens(128)
    |> llm_client.with_max_steps(3)

  assert settings.temperature == Some(0.2)
  assert settings.max_tokens == Some(128)
  assert settings.max_steps == Some(3)
  assert settings.provider_options_json == None
}

pub fn call_map_and_await_test() {
  let value =
    llm_client.succeed(40)
    |> llm_client.map(fn(number) { number + 2 })
    |> llm_client.await

  assert value == 42
}

pub fn generate_text_local_llm_test() {
  let request =
    llm_client.prompt(model: local_model, prompt: "Reply with one short word.")
    |> llm_client.with_settings(small_settings())

  request
  |> llm_client.generate_text
  |> llm_client.map(fn(result) {
    let assert Ok(response) = result
    assert string.length(response.text) > 0
  })
  |> llm_client.await
}

pub fn stream_text_local_llm_test() {
  reset_stream_deltas()

  let request =
    llm_client.prompt(
      model: local_model,
      prompt: "Reply with a short sentence.",
    )
    |> llm_client.with_settings(small_settings())

  llm_client.stream_text(request, record_stream_delta)
  |> llm_client.map(fn(result) {
    let assert Ok(response) = result
    assert string.length(response.text) > 0
    assert stream_delta_count() > 0
  })
  |> llm_client.await
}

pub fn structured_output_local_llm_test() {
  let schema =
    "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\"}},\"required\":[\"answer\"]}"

  let request =
    llm_client.prompt(
      model: local_model,
      prompt: "Return JSON only. Set answer to ok.",
    )
    |> llm_client.with_settings(small_settings())
    |> llm_client.with_output(llm_client.ObjectOutput(
      schema_json: schema,
      name: Some("answer"),
      description: Some("A tiny structured answer"),
    ))

  request
  |> llm_client.generate_text
  |> llm_client.map(fn(result) {
    let assert Ok(response) = result
    assert string.length(response.output_json) > 0
    assert string.contains(response.output_json, "answer")
  })
  |> llm_client.await
}

fn small_settings() {
  llm_client.default_settings()
  |> llm_client.with_temperature(0.0)
  |> llm_client.with_max_tokens(32)
}

@external(erlang, "llm_client_test_ffi", "reset_stream_deltas")
@external(javascript, "./llm_client_test_ffi.mjs", "resetStreamDeltas")
fn reset_stream_deltas() -> Nil

@external(erlang, "llm_client_test_ffi", "record_stream_delta")
@external(javascript, "./llm_client_test_ffi.mjs", "recordStreamDelta")
fn record_stream_delta(delta: String) -> Nil

@external(erlang, "llm_client_test_ffi", "stream_delta_count")
@external(javascript, "./llm_client_test_ffi.mjs", "streamDeltaCount")
fn stream_delta_count() -> Int
