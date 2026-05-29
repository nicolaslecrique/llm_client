# LLM Client

## Langauge context

This project is written in GLEAM. Useful links to code in gleam:

* GLEAM root documentation: https://gleam.run/documentation/
* GLEAM language tour, covering gleam syntax: https://tour.gleam.run/everything/
* GLEAM stdlib documentation: https://gleam-stdlib.hexdocs.pm/

## API

This project is a Gleam library, compatible with both BEAM and javascript targets, exposing an API to call any LLM (llm providers like claude, openai, mistral, azure, aws bedrock, ollama...) using an unified API.

The API exposed follows Vercel AI SDK Core client functions", minimally adapted to expose an idiomatic GLEAM library:

Functions covered:

* [generateText](https://ai-sdk.dev/docs/reference/ai-sdk-core/generate-text#generatetext)
* [streamText](https://ai-sdk.dev/docs/reference/ai-sdk-core/stream-text)

See the relevant documentation here:
* https://ai-sdk.dev/docs/ai-sdk-core/generating-text
* https://ai-sdk.dev/docs/ai-sdk-core/generating-structured-data
* https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling
* https://ai-sdk.dev/docs/foundations/providers-and-models

## Implementation

* For the JS target, it wraps [Vercel AI SDk Core](https://ai-sdk.dev/docs/ai-sdk-core)
* For ge BEAM target, it wraps [req_llm](https://github.com/agentjido/req_llm)

## Tests

All API functions are unit-tested on both targets, using the smallest local LLM possible