# llm_client

A Gleam LLM client with an API shaped after Vercel AI SDK Core's
`generateText` and `streamText`, adapted to idiomatic Gleam names:
`generate_text` and `stream_text`.

## Targets

- JavaScript wraps Vercel AI SDK Core (`ai`).
- BEAM wraps `req_llm` when it is available on the application code path.

## Example

```gleam
import llm_client

pub fn main() {
  let request =
    llm_client.prompt(
      model: "anthropic/claude-sonnet-4.5",
      prompt: "Write a vegetarian lasagna recipe for 4 people.",
    )

  llm_client.generate_text(request)
  |> llm_client.run(fn(result) {
    case result {
      Ok(response) -> {
        // response.text contains the generated text.
        Nil
      }
      Error(error) -> {
        // error.message contains the provider/runtime error.
        Nil
      }
    }
  })
}
```

## JavaScript setup

Consumers compiling to JavaScript must install the AI SDK package in their
runtime project. The local Ollama integration tests also use the AI SDK Ollama
community provider:

```sh
pnpm install
```

JavaScript supports the same local `ollama:` model prefix as BEAM.

## BEAM setup

Consumers compiling to Erlang/BEAM should add `req_llm` to the host Mix or
rebar application. `llm_client` calls `ReqLLM.generate_text/3` and
`ReqLLM.stream_text/3` through a small Erlang FFI shim.

For local development and tests, both targets support an `ollama:` model prefix:

```gleam
llm_client.prompt(model: "ollama:tinyllama:1.1b", prompt: "Hello")
```

The integration tests call a local Ollama server, using `tinyllama:1.1b` for
plain generation, streaming, and structured JSON-output checks.
