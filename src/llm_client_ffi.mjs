import { Result$Ok, Result$Error, List$isEmpty, List$NonEmpty$first, List$NonEmpty$rest } from "./gleam.mjs";
import { Option$isSome, Option$Some$0 } from "../gleam_stdlib/gleam/option.mjs";
import {
  GenerateTextResult$GenerateTextResult,
  StreamTextResult$StreamTextResult,
  Usage$Usage,
  LlmError$LlmError,
  Message$isSystemMessage,
  Message$isUserMessage,
  Message$isAssistantMessage,
  Message$isToolMessage,
  Message$SystemMessage$content,
  Message$UserMessage$content,
  Message$AssistantMessage$content,
  Message$ToolMessage$tool_call_id,
  Message$ToolMessage$content,
  Output$isTextOutput,
  Output$isJsonOutput,
  Output$isObjectOutput,
  Output$isArrayOutput,
  Output$isChoiceOutput,
  Output$JsonOutput$name,
  Output$JsonOutput$description,
  Output$ObjectOutput$schema_json,
  Output$ObjectOutput$name,
  Output$ObjectOutput$description,
  Output$ArrayOutput$element_schema_json,
  Output$ArrayOutput$name,
  Output$ArrayOutput$description,
  Output$ChoiceOutput$options,
  Output$ChoiceOutput$name,
  Output$ChoiceOutput$description,
  Tool$isExecuteTool,
  Tool$ExecuteTool$name,
  Tool$ExecuteTool$description,
  Tool$ExecuteTool$input_schema_json,
  Tool$ExecuteTool$strict,
  Tool$ExecuteTool$execute,
  Tool$NoExecuteTool$name,
  Tool$NoExecuteTool$description,
  Tool$NoExecuteTool$input_schema_json,
  Tool$NoExecuteTool$strict,
  TextRequest$TextRequest$model,
  TextRequest$TextRequest$prompt,
  TextRequest$TextRequest$system,
  TextRequest$TextRequest$messages,
  TextRequest$TextRequest$settings,
  TextRequest$TextRequest$tools,
  TextRequest$TextRequest$output,
  Settings$Settings$temperature,
  Settings$Settings$max_tokens,
  Settings$Settings$max_steps,
  Settings$Settings$provider_options_json,
} from "./llm_client.mjs";

export function succeed(value) {
  return { sync: true, value, promise: Promise.resolve(value) };
}

export function map(call, mapper) {
  if (call?.sync === true) {
    return succeed(mapper(call.value));
  }
  return asyncCall(Promise.resolve(call?.promise ?? call).then(mapper));
}

export function run(call, callback) {
  Promise.resolve(call?.promise ?? call).then(callback);
  return undefined;
}

export function awaitCall(call) {
  return call?.sync === true ? call.value : call?.promise ?? call;
}

export function generateText(request) {
  return asyncCall(Promise.resolve()
    .then(async () => {
      const ai = await import("ai");
      return ai.generateText(await toAiRequest(request, ai));
    })
    .then((result) => Result$Ok(toGenerateTextResult(result)))
    .catch((error) => Result$Error(toError(error))));
}

export function streamText(request, onText) {
  return asyncCall(Promise.resolve()
    .then(async () => {
      const ai = await import("ai");
      const result = ai.streamText({
        ...await toAiRequest(request, ai),
        onError: ({ error }) => {
          throw error;
        },
      });
      let text = "";
      for await (const delta of result.textStream) {
        text += delta;
        onText(delta);
      }
      return Result$Ok(await toStreamTextResult(result, text));
    })
    .catch((error) => Result$Error(toError(error))));
}

function asyncCall(promise) {
  return { sync: false, promise };
}

async function toAiRequest(request, ai) {
  const settings = TextRequest$TextRequest$settings(request);
  const model = TextRequest$TextRequest$model(request);
  const maxSteps = optionToValue(Settings$Settings$max_steps(settings));
  const aiRequest = {
    model: await toModel(model),
    tools: toTools(TextRequest$TextRequest$tools(request), ai),
    output: toOutput(TextRequest$TextRequest$output(request), ai, isOllamaModel(model)),
    ...jsonOption(Settings$Settings$provider_options_json(settings), "providerOptions"),
    ...optionProp(Settings$Settings$temperature(settings), "temperature"),
    ...optionProp(Settings$Settings$max_tokens(settings), "maxOutputTokens"),
  };
  if (maxSteps !== undefined) {
    aiRequest.stopWhen = ai.stepCountIs(maxSteps);
  }
  const prompt = optionToValue(TextRequest$TextRequest$prompt(request));
  const system = optionToValue(TextRequest$TextRequest$system(request));
  const messages = toMessages(TextRequest$TextRequest$messages(request));
  if (prompt !== undefined) {
    aiRequest.prompt = prompt;
  }
  if (system !== undefined) {
    aiRequest.system = system;
  }
  if (messages.length > 0) {
    aiRequest.messages = messages;
  }
  return aiRequest;
}

async function toModel(model) {
  if (model.startsWith("ollama:")) {
    const { ollama } = await import("ollama-ai-provider-v2");
    return ollama(model.slice("ollama:".length));
  }
  return model;
}

function toMessages(messages) {
  return listToArray(messages).map((message) => {
    if (Message$isSystemMessage(message)) {
      return { role: "system", content: Message$SystemMessage$content(message) };
    }
    if (Message$isUserMessage(message)) {
      return { role: "user", content: Message$UserMessage$content(message) };
    }
    if (Message$isAssistantMessage(message)) {
      return { role: "assistant", content: Message$AssistantMessage$content(message) };
    }
    if (Message$isToolMessage(message)) {
      return {
        role: "tool",
        content: [
          {
            type: "tool-result",
            toolCallId: Message$ToolMessage$tool_call_id(message),
            output: Message$ToolMessage$content(message),
          },
        ],
      };
    }
    return message;
  });
}

function isOllamaModel(model) {
  return model.startsWith("ollama:");
}

function toOutput(output, ai, ollamaJsonCompatibility) {
  if (Output$isTextOutput(output)) {
    return ai.Output.text();
  }
  if (Output$isJsonOutput(output)) {
    return ai.Output.json(named(Output$JsonOutput$name(output), Output$JsonOutput$description(output)));
  }
  if (Output$isObjectOutput(output)) {
    if (ollamaJsonCompatibility) {
      return ai.Output.json(named(Output$ObjectOutput$name(output), Output$ObjectOutput$description(output)));
    }
    return ai.Output.object({
      ...named(Output$ObjectOutput$name(output), Output$ObjectOutput$description(output)),
      schema: ai.jsonSchema(parseJson(Output$ObjectOutput$schema_json(output))),
    });
  }
  if (Output$isArrayOutput(output)) {
    if (ollamaJsonCompatibility) {
      return ai.Output.json(named(Output$ArrayOutput$name(output), Output$ArrayOutput$description(output)));
    }
    return ai.Output.array({
      ...named(Output$ArrayOutput$name(output), Output$ArrayOutput$description(output)),
      element: ai.jsonSchema(parseJson(Output$ArrayOutput$element_schema_json(output))),
    });
  }
  if (Output$isChoiceOutput(output)) {
    if (ollamaJsonCompatibility) {
      return ai.Output.json(named(Output$ChoiceOutput$name(output), Output$ChoiceOutput$description(output)));
    }
    return ai.Output.choice({
      ...named(Output$ChoiceOutput$name(output), Output$ChoiceOutput$description(output)),
      options: listToArray(Output$ChoiceOutput$options(output)),
    });
  }
  return ai.Output.text();
}

function toTools(tools, ai) {
  const pairs = listToArray(tools).map((item) => {
    if (Tool$isExecuteTool(item)) {
      const name = Tool$ExecuteTool$name(item);
      return [
        name,
        ai.tool({
          description: Tool$ExecuteTool$description(item),
          inputSchema: ai.jsonSchema(parseJson(Tool$ExecuteTool$input_schema_json(item))),
          strict: Tool$ExecuteTool$strict(item),
          execute: async (input) => parseJson(Tool$ExecuteTool$execute(item)(JSON.stringify(input))),
        }),
      ];
    }
    const name = Tool$NoExecuteTool$name(item);
    return [
      name,
      ai.tool({
        description: Tool$NoExecuteTool$description(item),
        inputSchema: ai.jsonSchema(parseJson(Tool$NoExecuteTool$input_schema_json(item))),
        strict: Tool$NoExecuteTool$strict(item),
      }),
    ];
  });
  return Object.fromEntries(pairs);
}

function toGenerateTextResult(result) {
  return GenerateTextResult$GenerateTextResult(
    result.text ?? "",
    String(result.finishReason ?? ""),
    toUsage(result.totalUsage ?? result.usage),
    jsonString(result.output),
    jsonString(result.toolCalls ?? []),
    jsonString(result.toolResults ?? []),
    jsonString(result),
  );
}

async function toStreamTextResult(result, text) {
  const [finishReason, usage, output] = await Promise.all([
    result.finishReason.catch(() => ""),
    result.totalUsage?.catch(() => undefined) ?? result.usage?.catch(() => undefined),
    result.output?.catch(() => undefined),
  ]);
  return StreamTextResult$StreamTextResult(
    text,
    String(finishReason ?? ""),
    toUsage(usage),
    jsonString(output),
    jsonString({ finishReason, usage, output }),
  );
}

function toUsage(usage) {
  return Usage$Usage(
    numberOrZero(usage?.inputTokens ?? usage?.promptTokens),
    numberOrZero(usage?.outputTokens ?? usage?.completionTokens),
    numberOrZero(usage?.totalTokens),
  );
}

function toError(error) {
  return LlmError$LlmError(
    String(error?.message ?? error),
    String(error?.name ?? "llm_error"),
    jsonString(error),
  );
}

function named(name, description) {
  return {
    ...optionProp(name, "name"),
    ...optionProp(description, "description"),
  };
}

function optionProp(option, key) {
  const value = optionToValue(option);
  return value === undefined ? {} : { [key]: value };
}

function jsonOption(option, key) {
  const value = optionToValue(option);
  return value === undefined ? {} : { [key]: parseJson(value) };
}

function optionToValue(option) {
  return Option$isSome(option) ? Option$Some$0(option) : undefined;
}

function listToArray(list) {
  const out = [];
  let cursor = list;
  while (!List$isEmpty(cursor)) {
    out.push(List$NonEmpty$first(cursor));
    cursor = List$NonEmpty$rest(cursor);
  }
  return out;
}

function parseJson(value) {
  if (value === "") {
    return undefined;
  }
  return JSON.parse(value);
}

function jsonString(value) {
  try {
    return JSON.stringify(value ?? null);
  } catch (_) {
    return "null";
  }
}

function numberOrZero(value) {
  return Number.isFinite(value) ? value : 0;
}
