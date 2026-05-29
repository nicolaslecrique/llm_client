# LLM Client

## API

This project is a GLEAM (https://gleam.run/documentation/) library exposing an API to call any LLM (llm providers like claude, openai, mistral, azure, aws bedrock, ollama...) using an unified API.

The API exposted to the library client is identical to Vercel AI SDK Core client functions "generateText" and "streamText", minimally adapted to expose an idiomatic GLEAM library:

* generateText, streamText

See for documentation:
* https://ai-sdk.dev/docs/ai-sdk-core/generating-text
* https://ai-sdk.dev/docs/ai-sdk-core/generating-structured-data
* https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling

## Implementation

* For the JS target, the GLEAM library wrap Vercel AI SDk Core
* For ge BEAM target, it wrap req_llm (https://github.com/agentjido/req_llm)

## Tests

All API functions are unit-tested using the smallest local LLM possible